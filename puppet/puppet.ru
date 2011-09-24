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

run lambda {|env|
	if env['REQUEST_METHOD'] == 'POST'
		return [200, {}, 'kay']
	end

	secure, method, headers, uri, data = begin
		Net::HTTP.get(URI.parse("http#{'s' if Torb::Config['secure']}://#{Torb::Config['master']}/json/#{Torb::Config['name']}/#{Torb::Config['key']}/#{env['REQUEST_PATH'][1 .. -1]}")).from_json
	rescue
		return [503, {}, '']
	end

	ap [secure, method, headers, uri, data]

	uri  = URI.parse(uri)
	http = PROXY.start(uri.host, uri.port)

	response = case method
		when 'GET'
			http.get(uri.path)

		when 'POST'

		when 'HEAD'

		# XXX: not necessary
		when 'PUT'

		# XXX: not necessary
		when 'DELETE'
	end

	code = response.code
	body = response.body.
		gsub(%r{http://(\w.*)\.onion}, "http#{?s if secure}://$1.#{Torb::Config['master']}").
		gsub(%r{https://(\w.*)\.onion}, "http#{?s if secure}://$1.ssl.#{Torb::Config['master']}")

	headers = Hash[response.each_header.map {|(name, value)|
		[name.gsub(/(\A|-)(.)/) {|match|
			match.upcase
		}, value]
	}]

	return [code, headers, body]
}
