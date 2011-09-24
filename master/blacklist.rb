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

require 'digest/sha2'
require 'yaml'

module Torb; Config = YAML.parse_file(ARGV.shift).transform; end

ARGV.each {|site|
	whole, name, port, path = site.match(%r{^(?:https?://)?(\w+)(?:\.onion)?(?::(\d+))?(/.*?)?$}).to_a

	puts "#{site} => #{Digest::SHA256.hexdigest(Torb::Config['salt'] + "#{name}#{":#{port}" if port}#{"|#{path}" if path}")}"
}
