Gem::Specification.new do |s|
  s.name = 'zenith'
  s.version = '0.1'
  s.summary = 'separated template system for CloudFormation.'
  s.author = 'Uneco'
  s.email = 'aoki@u-ne.co'
  s.homepage = 'https://github.com/uneco/zenith'
  s.license = 'MIT' 
  s.files = %w(README.md ) + Dir['lib/**/*.rb']
  s.platform = Gem::Platform::RUBY
  s.require_path = 'lib'
  s.required_ruby_version = '>= 2.3.3'
  s.add_dependency 'activesupport', '~> 5.0.1'
end
