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

require 'sinatra'
require 'digest/sha2'
require 'net/http'
require 'datamapper'
require 'yaml'
require 'json'
require 'haml'
require 'base64'
require 'mechanize'

require 'ap'

module Torb
	class Puppets < Array
		class Puppet
			attr_reader :host, :password

			def initialize (host, password)
				@host = host
				@password  = password

				@assigned = []

				ping
			end

			def name
				@name ||= Digest::SHA256.hexdigest(@host + Torb.config['salt'].to_s + @password)
			end

			def ping (timeout=nil)
				response = Net::HTTP.post_form(URI.parse("http://#{host}/"), {})
				@alive   = response.code == '200' && response.body == 'kay'
			rescue
				false
			end

			def alive?
				@alive
			end

			# TODO: implement load checking support
			def load
				0
			end

			def url_for (id, secure=true)
				"http#{?s if secure}://#{host}/#{id}"
			end
		end

		def initialize (puppets)
			puppets.each {|host, key|
				self << Puppet.new(host, key)
			}
		end

		def ping (timeout=nil)
			each {|puppet|
				puppet.ping
			}
		end

		def get (host)
			find {|puppet|
				puppet.host == host || puppet.name == host
			}
		end

		def best
			min {|a, b|
				a.load <=> b.load
			}
		end
	end

	module Models
		class Request
			include DataMapper::Resource

			belongs_to :session, key: true

			property :secure,  Boolean
			property :method,  String, length: 6
			property :headers, Object
			property :uri,     URI
			property :data,    Object
		end

		class Session
			include DataMapper::Resource

			property :id, String, length: 64, key: true
			property :jar, Object, default: Mechanize::CookieJar.new

			has 1, :request, constraint: :destroy
		end
	end

	def self.config (path=nil)
		return @config unless path

		@config = YAML.parse_file(path).transform.tap {|c|
			c['pages'].dup.each {|name, path|
				c['pages'][name] = Haml::Engine.new(File.read(path))
			}
		}
	end

	def self.puppets (puppets=nil)
		return @puppets unless puppets

		@puppets = Puppets.new(puppets)
	end

	config(ARGV.first || 'config.yml')
	puppets(config['puppets'])

	trap 'USR1' do
		config(ARGV.first || 'config.yml')
		puppets(config['puppets'])
	end
end

DataMapper::Model.raise_on_save_failure = true
DataMapper::setup :default, Torb.config['database']
DataMapper::finalize
DataMapper::auto_upgrade!

Thread.start {
	Torb.puppets.ping

	sleep 60
}

use Rack::Session::Cookie, key: 'torb', secret: Torb.config['salt'].reverse

helpers do
	def banned? (url)
		whole, name, port, path = url.match(%r{^(?:https?://)?(\w+)(?:\.onion)?(?::(\d+))?(/.*?)?$}).to_a

		digest = Digest::SHA256.hexdigest(Torb.config['salt'] + "#{name}#{":#{port}" if port}#{"|#{path}" if path}")

		Torb.config['blacklist'].any? {|banned|
			banned == digest
		}
	end

	def request_headers
		env.inject({}) {|headers, (name, value)|
			headers.tap {
				next unless name =~ /^http_(.*)/i

				name = $1.downcase.gsub('_', '-').gsub(/(\A|-)(.)/) {|match|
					match.upcase
				}

				headers[name] = value unless ['Version', 'Host', 'Connection', 'Cookie'].member?(name)
			}
		}
	end

	def save_request
		uri = "http#{@ssl ? ?s : nil}://#{@name}.onion#{":#{@port}" if @port}#{env['REQUEST_URI']}"

		halt 500 if banned?(uri)

		session[:id] ||= Digest::SHA256.hexdigest(Torb.config['salt'].to_s + rand.to_s)

		Torb::Models::Session.first_or_create(id: session[:id]).tap {|s|
			s.request = Torb::Models::Request.first_or_create(session: s).tap {|r|
				r.update(
					secure:  env['rack.url_scheme'] == 'https',
					method:  env['REQUEST_METHOD'],
					uri:     uri,
					headers: request_headers
				)
			}

			s.save
		}

		redirect Torb.puppets.best.url_for(session[:id], env['rack.url_scheme'] == 'https')
	end
end

get '/' do
 save_request if @name

 Torb.config['pages']['home'].render
end

# puppet handling
get '/puppet/fetch/request/:name/:password/:id' do |name, password, id|
	save_request if @name
	halt 500     unless Torb.puppets.get(name).password  == password
	halt 500     unless s = Torb::Models::Session.get(id)
	halt 500     unless r = s.request

	[r.secure, r.method, r.headers.tap { |h| h['Cookie'] = s.jar.cookies(URI.parse(r.uri)).map(&:to_s).join('; ') }, r.uri, r.data].to_json
end

get '/puppet/cookie/set/:name/:password/:domain/:id/:cookie' do |name, password, domain, id, cookie|
	save_request if @name
	halt 500     unless Torb.puppets.get(name).password  == password
	halt 500     unless s = Torb::Models::Session.get(id)

	Mechanize::Cookie.parse(URI.parse("http://#{domain}"), Base64.urlsafe_decode64(cookie)).each {|cookie|
		s.jar.add(URI.parse("http://#{domain}"), cookie)
	}

	s.save
end

# request saving
before do
	_, @name, @port, @ssl = request.env['HTTP_HOST'].match(/^(\w+)(?:\.(\d+))?(\.ssl)?\.#{Regexp.escape(Torb.config['domain'])}/).to_a
end

get '/*' do
	save_request if @name
end

post '/*' do
	save_request if @name
end
