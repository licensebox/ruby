require 'json'
require_relative '../lib/licensebox'
def run(r)
  case r['op']
  when 'derive'; return Licensebox.derive_binding(r['product'],r['source'],r['raw_id'])
  when 'native'; return Licensebox.native_binding(r['product'])
  when 'verify'; return Licensebox.verify_lease(r['token'],r['product'],r['keys'],r['now'])
  end
  Licensebox::Client.open(product: r['product'],keys: r['keys'] || {},version: 'conformance',server: r['server'],ca_bundle: r['ca_bundle'],directory: r['directory'],clock: -> {r['now']},machine_binding: -> {r['binding']},on_sign_in: ->(_u,_c) {}) do |c|
    case r['op']
    when 'sign_in'; c.sign_in(timeout: 3)
    when 'require'; c.require(r.fetch('module','core'))
    when 'repeat'; c.require('core'); c.require('core')
    when 'request'; c.request_access(['export'],note: 'café – test')
    when 'record'; c.record('export',success: true,elapsed: 0.125); c.record('export',success: false,elapsed: 0.025)
    when 'access-link'; c.access_link
    else; c.public_send(r['op'])
    end
  end
end
begin
  puts JSON.generate(ok: true,value: run(JSON.parse(STDIN.read)))
rescue Licensebox::Error => e
  puts JSON.generate(ok: false,error: e.code)
end
