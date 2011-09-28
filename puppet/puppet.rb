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

require 'optparse'

options = {}

OptionParser.new do |o|
	options[:config] = 'config.yml'

	o.on '-c', '--config PATH', 'set config file path' do |value|
		options[:config] = value
	end
end.parse!

options[:config] ||= ARGV.shift

require 'eventmachine'
require 'evma_httpserver'
require 'em-http-request'

require 'yaml'
require 'json'
require 'base64'

require 'ap'

module Torb
	def self.config (path=nil)
		return @config unless path

		@config = YAML.parse_file(path).transform
	end

	def self.proxy
		whole, host, port = Torb.config['proxy'].match(/^(.*?):(.*?)$/).to_a

		{ :host => host, :port => port.to_i, :type => :socks5 }
	end

	def self.url
		"http#{'s' if Torb.config['secure']}://#{Torb.config['master']}"
	end
end

Torb.config(options[:config])
trap 'USR1' do
	Torb.config(options[:config])
end

class Handler < EventMachine::Connection
	include EventMachine::HttpServer

	def process_http_request
		# the http request details are available via the following instance variables:
		#   @http_protocol
		#   @http_request_method
		#   @http_cookie
		#   @http_if_none_match
		#   @http_content_type
		#   @http_path_info
		#   @http_request_uri
		#   @http_query_string
		#   @http_post_content
		#   @http_headers

		response = EventMachine::DelegatedHttpResponse.new(self)

		if @http_request_method == 'POST'
			response.status  = 200
			response.content = 'kay'
			response.send_response

			return
		end

		whole, id, rid = @http_request_uri.match(%r{^/(\w+)/(\d+)(/.*)?$}).to_a

		EventMachine::HttpRequest.new("#{Torb.url}/puppet/fetch/request/#{Torb.config['name']}/#{Torb.config['password']}/#{id}/#{rid}").get.tap {|http|
			http.callback {
				secure, method, headers, uri, data = begin
					JSON.parse(http.response)
				rescue => e
					response.status = 503
					response.send_response
					next
				end

				ssl     = uri.start_with?('https')
				service = uri.match(%r{/(.*?).onion})[1]

				puts "Going on #{uri}"

				EventMachine::HttpRequest.new(uri, { :proxy => Torb.proxy }).send(method.downcase, { :head => headers }).tap {|http|
					http.headers {|headers|
						response.status  = http.response_header.status
						response.headers = Hash[http.response_header.map {|name, value|
							[name.downcase.gsub('_', '-').gsub(/(\A|-)(.)/) {|match|
								match.upcase
							}, value]
						}]

						response.headers.delete('Transfer-Encoding')

						if response.headers['Set-Cookie']
							EventMachine::HttpRequest.new("#{Torb.url}/puppet/cookie/set/#{Torb.config['name']}/#{Torb.config['key']}/#{id}/#{Base64.urlsafe_encode64(response.headers.delete('Set-Cookie'))}").get.tap {|http|
								http.callback { }
							}
						end

						if response.headers['Content-Type'] == 'text/html'
							http.callback {
								response.content = http.response.
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

								response.send_response
							}
						else
							http.callback {
								response.send_trailer
								response.close_connection_after_writing
							}

							http.stream {|chunk|
								response.chunk chunk
								response.send_chunks
							}
						end
					}
				}
			}
		}
	end
end

EventMachine.run {
  EventMachine.epoll

	whole, host, port = Torb.config['host'].match(/^(.*?):(.*?)$/).to_a

  EventMachine.start_server(host, port.to_i, Handler)

  puts "Listening on #{host}:#{port}..."
}
