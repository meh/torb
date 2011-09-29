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

$options = {}

OptionParser.new do |o|
	$options[:config] = 'config.yml'

	o.on '-d', '--database DATABASE', 'set database URI' do |uri|
		$options[:database] = uri
	end

	o.on '-c', '--config PATH', 'set config file path' do |value|
		$options[:config] = value
	end

	o.on '-q', '--quiet', 'make it STFU' do
		$options[:quiet] = true
	end
end.parse!

$options[:config] ||= ARGV.shift

require 'eventmachine'
require 'evma_httpserver'
require 'em-http-request'

require 'yaml'
require 'memoized'

module Torb
	Version = '0.1'

	module Models
		class Config
			class Piece
				include DataMapper::Resource

				belongs_to :config

				property :path, String, key: true
				property :value, Object
			end

			include DataMapper::Resource

			property :id, Serial
			property :created_at, DateTime

			has n, :pieces
		end

		class Session
			include DataMapper::Resource

			property :id, String, length: 64, key: true
			property :jar, Object, default: Mechanize::CookieJar.new

			has n, :requests, constraint: :destroy

			property :created_at, DateTime
		end
	end

	module Config
		class << Config
			def to_hash
				Hash[Models::Config.first_or_create.pieces.to_a.map {|piece|
					[piece.path, piece.value]
				}]
			end

			def get (*path)
				Models::Config.first_or_create.pieces.get(path.join(?.)).value rescue nil
			end; alias [] get

			def set (*path, value)
				Models::Config.first_or_create.pieces.first_or_create(path: path.join(?.)).update(value: value)
			end; alias []= set
		end
	end

	def self.config (path=nil)
		return @config unless path

		memoize_clear

		@config = YAML.parse_file(path).transform
	end

	singleton_memoize
	def self.proxy
		whole, host, port = Torb.config['proxy'].match(/^(.*?):(.*?)$/).to_a

		{ host: host, port: port.to_i, type: :socks5 }
	end

	singleton_memoize
	def self.request_options
		{ proxy: Torb.proxy, connect_timeout: 0, inactivity_timeout: 0 }
	end
end

if !$options[:database]
	$options[:database] = ARGV.shift or fail 'no database URI was passed'
end

DataMapper::Model.raise_on_save_failure = true
DataMapper::setup :default, $options[:database]
DataMapper::finalize
DataMapper::auto_upgrade!

if $options[:config]
	if ARGV.empty?
		Torb::Config.to_hash.each {|name, value|
			puts "#{name}: #{value}"
		}

		exit!
	end

	ARGV.each {|path|
		path, value = if path.include?(?=)
			path, value = path.split(?=, 2)

			Torb::Config[path] = value

			[path, value]
		else
			[path, Torb::Config[path]]
		end

		puts "#{path}: #{value.inspect}"
	}

	exit!
end

Torb.config($options[:config])
trap 'USR1' do
	Torb.config($options[:config])
end

class Handler < EventMachine::Connection
	include EventMachine::HttpServer

	def process_http_request
		response = EventMachine::DelegatedHttpResponse.new(self)

		method  = @http_request_method.upcase
		data    = @http_post_data
		headers = Hash[@http_headers.split(?\0).map {|header|
			name, value = header.split(/\s*:\s*/, 2)

			[name.downcase.gsub('_', '-').gsub(/(\A|-)(.)/) {|match|
				match.upcase
			}, value]
		}].tap {|h|
			h['Connection'] = 'close'
			h['User-Agent'] = "torb/#{Torb::Version}"
		}

		_, service, port, ssl = headers['Host'].match(/^(\w+)(?:\.(\d+))?(\.ssl)?\./).to_a
		uri = "http#{ssl ? ?s : nil}://#{name}.onion#{":#{port}" if port}#{@http_request_uri}"

		puts "#{method} #{uri}" unless $options[:quiet]

		EventMachine::HttpRequest.new(uri, Torb.request_options).send(method.downcase, { head: headers }).tap {|http|
			http.errback {
				response.status = 503
				response.send_response
			}

			http.headers {|headers|
				response.status  = http.response_header.status
				response.headers = Hash[http.response_header.map {|name, value|
					[name.downcase.gsub('_', '-').gsub(/(\A|-)(.)/) {|match|
						match.upcase
					}, value]
				}].tap {|h|
					h.delete 'Transfer-Encoding'
					h.delete 'Content-Length'
				}

				if response.headers['Content-Type'] =~ %r(text/(html|css))
					http.callback {
						response.content = http.response.tap {|s|
							s.gsub!(%r(http://(\w*)\.onion), "http#{?s if secure}://\\1.#{Torb.config['master']}")
							s.gsub!(%r(https://(\w*)\.onion), "http#{?s if secure}://\\1.ssl.#{Torb.config['master']}")
						}

						response.send_response
					}
				else
					http.stream {|chunk|
						response.chunk chunk
						response.send_chunks
					}

					http.callback {
						response.send_trailer
						response.close_connection_after_writing
					}
				end
			}
		}
	end
end

EventMachine.run {
  EventMachine.epoll

	whole, host, port = Torb.config['bind'].match(/^(.*?):(.*?)$/).to_a

  EventMachine.start_server(host, port.to_i, Handler)

  puts "Listening on #{host}:#{port}..."
}
