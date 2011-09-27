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
	o.on '-c', '--config', 'enable config mode' do
		options[:config] = true
	end

	o.on '-d', '--database DATABASE', 'set database URI' do |uri|
		options[:database] = uri
	end
end.parse!

require 'sinatra'
require 'datamapper'

require 'digest/sha2'
require 'net/http'
require 'json'
require 'haml'
require 'base64'
require 'mechanize'

require 'ap'

module Torb
	Version = '0.1'

	class Puppets < Array
		class Puppet
			attr_reader :name, :host, :password

			def initialize (name, host, password)
				@name      = name
				@host      = host
				@password  = password

				ping
			end

			def name
				@name ||= Digest::SHA256.hexdigest(@host + Torb::Config[:salt].to_s + @password)
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

			def url_for (id, rid, secure=true)
				"http#{?s if secure}://#{host}/#{id}/#{rid}"
			end
		end

		def initialize (puppets)
			puppets.each {|name, (host, key)|
				self << Puppet.new(name, host, key)
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
			select {|o|
				o.available?
			}.min {|a, b|
				a.load <=> b.load
			}
		end
	end

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

		class Request
			include DataMapper::Resource

			belongs_to :session

			property :id, Serial

			property :secure,  Boolean
			property :method,  String, length: 6
			property :headers, Object
			property :uri,     URI
			property :data,    Object

			property :created_at, DateTime
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

	def self.puppets (reload=false)
		return @puppets unless reload

		@puppets = Puppets.new(Hash[Models::Config.first_or_create.pieces.all(:path.like => 'puppets.%').map {|piece|
			[piece.path.split(?.).last, piece.value.split(/\s*;\s*/)]
		}])
	end
end

if !options[:database]
	options[:database] = ARGV.shift or fail 'no database URI was passed'
end

DataMapper::Model.raise_on_save_failure = true
DataMapper::setup :default, options[:database]
DataMapper::finalize
DataMapper::auto_upgrade!

if options[:config]
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

Torb.puppets(true)
trap 'USR1' do
	Torb.puppets(true)
end

use Rack::Session::Cookie, key: 'torb', secret: Torb::Config[:salt].reverse

helpers do
	def banned? (url)
		whole, name, port, path = url.match(%r{^(?:https?://)?(\w+)(?:\.onion)?(?::(\d+))?(/.*?)?$}).to_a

		digest = Digest::SHA256.hexdigest(Torb::Config[:salt] + "#{name}#{":#{port}" if port}#{"|#{path}" if path}")

		(Torb::Config[:blacklist] || []).any? {|banned|
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

		session[:id] ||= Digest::SHA256.hexdigest(Torb::Config[:salt].to_s + rand.to_s)
		request_id     = nil

		Torb::Models::Session.first_or_create(id: session[:id]).tap {|s|
			s.requests.create.tap {|r|
				r.update(
					secure:  env['rack.url_scheme'] == 'https',
					method:  env['REQUEST_METHOD'],
					uri:     uri,
					headers: request_headers
				)

				request_id = r.id
			}

			s.save
		}

		redirect Torb.puppets.best.url_for(session[:id], request_id, env['rack.url_scheme'] == 'https')
	end
end

# server index
get '/' do
 save_request if @name

 Torb::Config[:pages, :home].render
end

# puppet handling
get '/puppet/fetch/request/:name/:password/:id/:rid' do |name, password, id, rid|
	save_request if @name
	halt 500     unless Torb.puppets.get(name).password  == password
	halt 500     unless s = Torb::Models::Session.get(id)
	halt 500     unless r = s.requests.first(id: rid)

	[r.secure, r.method, r.headers.tap {|h|
		s.jar.cookies(URI.parse(r.uri)).map(&:to_s).join('; ').tap {|c|
			h['Cookie'] = c unless c.empty?
		}

		h['User-Agent'] = "torb/#{Torb::Version}"
	}, r.uri, r.data].to_json
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
	_, @name, @port, @ssl = request.env['HTTP_HOST'].match(/^(\w+)(?:\.(\d+))?(\.ssl)?\./).to_a
end

get '/*' do
	save_request if @name
end

post '/*' do
	save_request if @name
end

# start the time dependant things thread
Thread.start {
	Torb.puppets.ping

	sleep 60
}
