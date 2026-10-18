require 'tmpdir'
require_relative '../lib/licensebox'
def assert(v); raise 'assertion failed' unless v; end
assert Licensebox.derive_binding('demo','linux-machine-id',"12345678123456789abc1234567890ab\0").start_with?('m1:linux-machine-id:')
begin; Licensebox.verify_lease('bad','demo',{},0); raise 'accepted bad lease'; rescue Licensebox::Error => e; assert e.code == 'malformed'; end
Dir.mktmpdir do |dir|
  c = Licensebox::Client.new(product: 'demo',keys: {'test-key' => 'A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg'},directory: dir,machine_binding: -> {raise 'synthetic callback failure'})
  begin; c.sign_in(timeout: 0.1); raise 'callback escaped'; rescue Licensebox::Error => e; assert e.code == 'callback_error'; ensure; c.close; end
  c.close
end
puts 'Ruby binding checks passed'
