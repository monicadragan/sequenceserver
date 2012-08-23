#!/usr/bin/env ruby
# Usage:
#
# run all test suites
#
#     $ tests/run tests/test_js_hint.rb
#
# run a particular test suite
#
#     $ tests/run tests/test_js_hint.rb public/js/sequenceserver.js

# jshint executable
jshint = `which jshint`.chomp

# install if jshint not present
if jshint.empty?
  system 'npm install jshint'
  jshint = File.expand_path(File.join('node_modules', 'jshint', 'bin', 'hint'))
end

# SS root directory
root = File.dirname(File.dirname(__FILE__))

# jshint specification
jshintrc = File.join(root, '.jshintrc')

# get list of scripts to run through jshint
scripts = if ARGV.empty?
            %w|jquery.index.js sequenceserver.js jquery.scrollspy.js sequenceserver.blast.js|.map do |script|
              File.join(root, 'lib', 'sequenceserver', 'web_blast', 'public', 'js', script)
            end
          else
            ARGV.map {|path| File.expand_path(path)}
          end

# run _all_ scripts through jshint; exit with a failure status if any script
# fails
success = true
scripts.each do |script|
  output = `#{jshint} --config #{jshintrc} #{script}`
  unless $?.success?
    puts
    puts "****************************************"
    puts "JSHint test failed for '#{script}'."
    puts
    puts output
    puts "****************************************"
    puts
    success = false
  end
end

exit success
