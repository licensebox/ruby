# frozen_string_literal: true
require 'fiddle/import'
require 'json'
module Licensebox
  VERSION = '0.1.0'
  class Error < StandardError
    attr_reader :code
    def initialize(code, detail = code); @code = code; super("licensebox: #{detail}"); end
  end
  module Native
    extend Fiddle::Importer
    dlload ENV['LICENSEBOX_LIBRARY'] || File.join(ENV.fetch('LICENSEBOX_LIB_DIR', ''), 'liblicensebox.so')
    extern 'int lb_client_create_json(const char*, void*, void*)'
    extern 'int lb_client_call_json(void*, const char*, const char*, void*)'
    extern 'void lb_client_destroy(void*)'
    extern 'void lb_free(void*)'
    extern 'char* lb_result_code(int)'
    extern 'char* lb_error_code(void*)'
    extern 'char* lb_error_message(void*)'
    extern 'int lb_native_binding(const char*, void*, size_t)'
    extern 'int lb_derive_binding(const char*, const char*, const char*, void*, size_t)'
    extern 'int lb_verify_lease_json(const char*, const char*, const char*, double, void*)'
  end
  def self.argument(value)
    raise Error.new('invalid_argument') unless value.is_a?(String) && !value.include?("\0")
    value
  end
  def self.error(result, handle = nil)
    code = Native.lb_result_code(result).to_s
    detail = code
    if handle && code != 'invalid_argument'
      saved = Native.lb_error_code(handle).to_s
      code = saved unless saved == 'ok'
      detail = Native.lb_error_message(handle).to_s
    end
    Error.new(code, detail)
  end
  def self.slot; Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE).tap { |p| p[0, Fiddle::SIZEOF_VOIDP] = [0].pack('J') }; end
  def self.pointer(slot); Fiddle::Pointer.new(slot[0, Fiddle::SIZEOF_VOIDP].unpack1('J')); end
  def self.output(ptr)
    raise Error.new('protocol_error') if ptr.null?
    begin; JSON.parse(ptr.to_s); ensure; Native.lb_free(ptr); end
  end
  def self.derive_binding(product, source, raw)
    raw = raw.sub(/\x00+\z/, '')
    raise Error.new('identity_unavailable') if raw.include?("\0")
    out = Fiddle::Pointer.malloc(128, Fiddle::RUBY_FREE)
    r = Native.lb_derive_binding(argument(product), argument(source), raw, out, 128)
    raise error(r) unless r.zero?
    out.to_s
  end
  def self.native_binding(product)
    out = Fiddle::Pointer.malloc(128, Fiddle::RUBY_FREE)
    r = Native.lb_native_binding(argument(product), out, 128)
    raise error(r) unless r.zero?
    out.to_s
  end
  def self.verify_lease(token, product, keys, now)
    raise Error.new('invalid_argument') unless now.finite?
    keys.each { |k,v| argument(k); argument(v) }
    out = slot
    r = Native.lb_verify_lease_json(argument(token), argument(product), JSON.generate(keys), now, out)
    ptr = pointer(out)
    unless r.zero?; Native.lb_free(ptr); raise error(r); end
    output(ptr)
  end
  # Trusted platform seams are callables, never serialized options. Callbacks may
  # not reenter this client. All callbacks stay strongly referenced until close.
  class Client
    def initialize(product:, keys:, version: '', server: nil, directory: nil, ca_bundle: nil,
                   clock: nil, machine_binding: nil, on_sign_in: nil, cancelled: nil)
      options = { product: Licensebox.argument(product), keys: keys, version: Licensebox.argument(version) }
      keys.each { |k,v| Licensebox.argument(k); Licensebox.argument(v) }
      {server: server, directory: directory, ca_bundle: ca_bundle}.each { |k,v| options[k] = Licensebox.argument(v) unless v.nil? }
      @mutex = Mutex.new
      @callbacks = []
      wrap = ->(result, types, fallback, &block) {
        cb = Fiddle::Closure::BlockCaller.new(result, types) { |*args| begin; block.call(*args); rescue Exception => e; @failure = e; fallback; end }
        @callbacks << cb
        cb.to_i
      }
      p = Fiddle::TYPE_VOIDP; i = Fiddle::TYPE_INT
      sign = on_sign_in ? wrap.call(Fiddle::TYPE_VOID, [p,p,p], nil) { |_,u,c| on_sign_in.call(u.to_s,c.to_s) } : 0
      clk = clock ? wrap.call(Fiddle::TYPE_DOUBLE, [p], 0.0) { |_| v = Float(clock.call); raise Error.new('invalid_argument') unless v.finite?; v } : 0
      bind = machine_binding ? wrap.call(i, [p,p,Fiddle::TYPE_SIZE_T], 1) { |_,out,n| s = Licensebox.argument(machine_binding.call); raise Error.new('invalid_argument') if s.bytesize >= n; out[0,s.bytesize+1] = s + "\0"; 0 } : 0
      cancel = wrap.call(i, [p], 1) { |_| @failure || (cancelled && cancelled.call) ? 1 : 0 }
      @structure = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP * 5, Fiddle::RUBY_FREE)
      @structure[0,Fiddle::SIZEOF_VOIDP * 5] = [0,sign,clk,bind,cancel].pack('J*')
      out = Licensebox.slot
      r = Native.lb_client_create_json(JSON.generate(options), @structure, out)
      @handle = Licensebox.pointer(out)
      if @failure || !r.zero?
        Native.lb_client_destroy(@handle) unless @handle.null?
        @handle = nil
        raise(@failure ? Error.new('callback_error', @failure.message) : Licensebox.error(r))
      end
    end
    def synchronize
      raise Error.new('invalid_argument', 'callbacks must not reenter client') if @owner == Thread.current
      @mutex.synchronize do
        @owner = Thread.current
        begin; yield; ensure; @owner = nil; end
      end
    end
    def close
      synchronize do
        Native.lb_client_destroy(@handle) if @handle
        @handle = nil
        @callbacks.clear
      end
    end
    def self.open(**options)
      client = new(**options)
      begin; yield client; ensure; client.close; end
    end
    def call(operation, arguments = {})
      synchronize do
        raise Error.new('invalid_argument', 'client closed') unless @handle
        out = Licensebox.slot
        r = Native.lb_client_call_json(@handle, operation, JSON.generate(arguments), out)
        ptr = Licensebox.pointer(out)
        if @failure || !r.zero?
          Native.lb_free(ptr)
          failure = @failure; @failure = nil
          raise(failure ? Error.new('callback_error', failure.message) : Licensebox.error(r, @handle))
        end
        Licensebox.output(ptr)
      end
    end
    private :call, :synchronize
    def lease; call('lease'); end
    def heartbeat(module_name); call('heartbeat', module: Licensebox.argument(module_name)); end
    def require(module_name); call('require', module: Licensebox.argument(module_name)); end
    def status; call('status'); end
    def sign_in(timeout: 0); raise Error.new('invalid_argument') unless timeout.finite?; call('sign_in', timeout: timeout); end
    def logout; call('logout'); end
    def modules; call('modules'); end
    def requests; call('requests'); end
    def request_access(modules, note: ''); call('request', modules: modules.map { |v| Licensebox.argument(v) }, note: Licensebox.argument(note)); end
    def access_link; call('access-link'); end
    def record(command, success:, elapsed:)
      raise Error.new('invalid_argument') unless [true,false].include?(success) && elapsed.finite? && elapsed >= 0
      call('record', command: Licensebox.argument(command), success: success, elapsed: elapsed)
    end
  end
end
