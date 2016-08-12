# encoding: utf-8
# author: Dominik Richter
# author: Christoph Hartmann

require 'rspec/core/formatters/base_text_formatter'
require 'pry'

module Inspec
  # A pry based shell for inspec. Given a runner (with a configured backend and
  # all that jazz), this shell will produce a pry shell from which you can run
  # inspec/ruby commands that will be run within the context of the runner.
  class Shell
    attr_reader :current_line

    def initialize(runner)
      @runner = runner
      @current_line = 0
    end

    def start(opts)
      # Create an in-memory empty profile so that we can add tests to it later.
      # This context lasts for the duration of this "start" method call/pry
      # session.
      @ctx = @runner.add_target({'shell_context.rb' => ''}, opts)
      configure_pry
      binding.pry
      @ctx = nil
    end

    def configure_pry
      # Remove all hooks and checks
      Pry.hooks.clear_all
      that = self

      # Add the help command
      Pry::Commands.block_command 'help', 'Show examples' do |resource|
        that.help(resource)
      end

      # configure pry shell prompt
      Pry.config.prompt_name = 'inspec'
      Pry.prompt = [proc { "#{readline_ignore("\e[0;32m")}#{Pry.config.prompt_name}:#{that.current_line}> #{readline_ignore("\e[0m")}" }]

      # Add a help menu as the default intro
      Pry.hooks.add_hook(:before_session, 'inspec_intro') do
        intro
      end

      # Evaluate the command given by the user as if it were inside a profile
      # context (with all of the DSL available to us).
      Pry.hooks.add_hook(:before_eval, 'inspec_before_eval') do |code, binding, pry|
        before_eval(code)
      end
    end

    def before_eval(code)
      @current_line += 1
      @runner.reset_tests
      test = {
        content: code,
        ref: 'InSpec-Shell',
        line: current_line,
      }
      @runner.append_content(@ctx, test, [])
      @runner.run
    end

    def readline_ignore(code)
      "\001#{code}\002"
    end

    def mark(x)
      "#{readline_ignore("\033[1m")}#{x}#{readline_ignore("\033[0m")}"
    end

    def print_example(example)
      # determine min whitespace that can be removed
      min = nil
      example.lines.each do |line|
        if line.strip.length > 0 # ignore empty lines
          line_whitespace = line.length - line.lstrip.length
          min = line_whitespace if min.nil? || line_whitespace < min
        end
      end
      # remove whitespace from each line
      example.gsub(/\n\s{#{min}}/, "\n")
    end

    def intro
      puts 'Welcome to the interactive InSpec Shell'
      puts "To find out how to use it, type: #{mark 'help'}"
      puts
    end

    def help(resource = nil)
      if resource.nil?

        ctx = @runner.backend
        puts <<EOF

Available commands:

    `[resource]` - run resource on target machine
    `help resources` - show all available resources that can be used as commands
    `help [resource]` - information about a specific resource
    `exit` - exit the InSpec shell

You can use resources in this environment to test the target machine. For example:

    command('uname -a').stdout
    file('/proc/cpuinfo').content => "value",

You are currently running on:

    OS platform:  #{mark ctx.os[:name] || 'unknown'}
    OS family:  #{mark ctx.os[:family] || 'unknown'}
    OS release: #{mark ctx.os[:release] || 'unknown'}

EOF
      elsif resource == 'resources'
        resources
      elsif !Inspec::Resource.registry[resource].nil?
        puts <<EOF
#{mark 'Name:'} #{resource}

#{mark 'Description:'}

#{Inspec::Resource.registry[resource].desc}

#{mark 'Example:'}
#{print_example(Inspec::Resource.registry[resource].example)}

#{mark 'Web Reference:'}

https://github.com/chef/inspec/blob/master/docs/resources.rst##{resource}

EOF
      else
        puts 'Only the following resources are available:'
        resources
      end
    end

    def resources
      puts Inspec::Resource.registry.keys.join(' ')
    end
  end

  class NoSummaryFormatter < RSpec::Core::Formatters::BaseTextFormatter
    RSpec::Core::Formatters.register self, :dump_summary

    def dump_summary(*_args)
      # output nothing
    end
  end
end
