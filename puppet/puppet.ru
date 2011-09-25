#! /usr/bin/env ruby
# Copyleft meh. [http://meh.paranoid.pk | meh@paranoici.org]
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with This program. If not, see <http://www.gnu.org/licenses/>.

require 'yaml'
require 'json'
require 'socksify/http'
require 'memoized'
require 'base64'

require 'ap'

module Torb
	def self.config (path=nil)
		return @config unless path

		@config = YAML.parse_file(path).transform
	end

	def self.proxy (proxy=nil)
		return @proxy unless proxy

		whole, host, port = proxy.match(/^(.*?):(.*?)$/).to_a

		@proxy = Net::HTTP.SOCKSProxy(host, port.to_i)
	end

	config(ARGV.first || 'config.yml')
	proxy(Torb.config['proxy'])

	trap 'USR1' do
		config(ARGV.first || 'config.yml')
		proxy(Torb.config['proxy'])
	end
end

use Rack::ContentLength
use Rack::CommonLogger

run lambda {|env|
	if env['REQUEST_METHOD'] == 'POST'
		return [200, {}, ['kay']]
	end

	secure, method, headers, uri, data = begin
		JSON.parse(Net::HTTP.get(URI.parse("http#{'s' if Torb.config['secure']}://#{Torb.config['master']}/puppet/fetch/request/#{Torb.config['name']}/#{Torb.config['key']}/#{env['REQUEST_PATH'][1 .. -1]}")))
	rescue
		return [503, {}, ['']]
	end

	ssl     = uri.start_with?('https')
	service = uri.match(%r{/(.*?).onion})[1]

	uri  = URI.parse(uri)
	http = Torb.proxy.start(uri.host, uri.port)

	response = case method
		when 'GET'
			http.get(uri.path, headers)

		when 'POST'

		when 'HEAD'

		# XXX: not necessary
		when 'PUT'

		# XXX: not necessary
		when 'DELETE'
	end

	code    = response.code
	body    = response.body
	headers = Hash[response.each_header.map {|name, value|
		[name.gsub(/(\A|-)(.)/) {|match|
			match.upcase
		}, value]
	}.compact]

	if headers['Content-Type'] == 'text/html'
		body = body.
			gsub(%r{http://(\w*)\.onion}, "http#{?s if secure}://\\1.#{Torb.config['master']}").
			gsub(%r{https://(\w*)\.onion}, "http#{?s if secure}://\\1.ssl.#{Torb.config['master']}").
			gsub(%r{href=['"](.*?)['"]}) {|match|
				uri = match.match(%r{href=['"](.*?)['"]$})[1]

				if (URI.parse(uri).scheme rescue false)
					match
				else
					"href='http#{?s if secure}://#{service}.#{'ssl.' if ssl}#{Torb.config['master']}/#{uri}'"
				end
			}
	end

	headers.delete('Transfer-Encoding')

	if headers['Set-Cookie']
		Net::HTTP.get(URI.parse("http#{'s' if Torb.config['secure']}://#{Torb.config['master']}/puppet/cookie/set/#{Torb.config['name']}/#{Torb.config['key']}/#{env['REQUEST_PATH'][1 .. -1]}/#{Base64.urlsafe_encode64(headers.delete('Set-Cookie'))}"))
	end

	return [code, headers, [body]]
}
