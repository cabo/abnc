Gem::Specification.new do |s|
  s.name = "abnc"
  s.version = "0.1.1"
  s.summary = "RFC 5234+7405 ABNF compiler-let"
  s.description = %q{Shifty support for tools based on IETF's ABNF}
  s.author = "Carsten Bormann"
  s.email = "cabo@tzi.org"
  s.license = "Apache-2.0"
  s.homepage = "http://github.com/cabo/abnc"
  s.has_rdoc = false
  s.files = Dir['lib/**/*.rb'] + %w(abnc.gemspec)
  s.required_ruby_version = '>= 1.9.2'

  s.require_paths = ["lib"]
end
