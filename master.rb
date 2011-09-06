#--
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
#++

require 'sinatra'
require 'datamapper'
require 'yaml'
require 'json'
require 'haml'

require 'ap'

module Torb
  Config = YAML.parse_file(ARGV.shift).transform.tap {|c|
    c['pages'].dup.each {|name, content|
      c['pages'][name] = Haml::Engine.new(content)
    }
  }
end

module Models
  class Request
    include DataMapper::Resource

    belongs_to :session, key: true

    property :method,  String, length: 6
    property :headers, Object
    property :uri,     URI
    property :data,    Object
  end

  class Session
    include DataMapper::Resource

    property :id, String, length: 40, key: true

    has 1, :request, constraint: :destroy
  end

  DataMapper::Model.raise_on_save_failure = true
  DataMapper::setup :default, Torb::Config['database']
  DataMapper::finalize
  DataMapper::auto_upgrade!
end

use Rack::Session::Cookie, key: 'torb', secret: Torb::Config['salt'].reverse

helpers do
  def request_headers
    env.inject({}) {|headers, (name, value)|
      headers.tap {
        next unless name =~ /^http_(.*)/i

        name = $1.downcase.gsub('_', '-').gsub(/(\A|-)(.)/) {|match|
          match.upcase
        }

        headers[name] = value unless ['Version', 'Host', 'Connection'].member?(name)
      }
    }
  end

  def save_request
    session[:id] ||= Digest::SHA1.hexdigest(Torb::Config['salt'].to_s + rand.to_s)

    Models::Session.first_or_create(id: session[:id]).tap {|s|
      s.request = Models::Request.first_or_create(session: s).tap {|r|
        r.update(
          method:  env['REQUEST_METHOD'],
          uri:     "http#{@ssl ? ?s : nil}://#{@name}.onion#{":#{@port}" if @port}#{env['REQUEST_URI']}",
          headers: request_headers
        )
      }
    }

    redirect best_node
  end

  def best_node
    
  end
end

before do
  _, @name, @port, @ssl = request.env['HTTP_HOST'].match(/^(\w+)(?:\.(\d+))?(\.ssl)?\.#{Regexp.escape(Torb::Config['domain'])}/).to_a
end

get '/' do
 save_request if @name 

 Torb::Config['pages']['home'].render 
end

get '/json/:name/:password/:id' do |name, password, id|
  save_request if @name
  halt 500     if Torb::Config['puppets'][name] == password
  halt 500     unless r = Models::Session.get(id).request
    
  [r.method, r.headers, r.uri, r.data].to_json
end

get '/*' do
  save_request if @name
end

post '/*' do
  save_request if @name
end
