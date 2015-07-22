require 'timeout'
require 'open3'

module Calabash
  module Android
    # @!visibility private
    class ADB
      # @!visibility private
      class ADBCallError < StandardError
        attr_reader :stderr, :stdout

        def initialize(message, stderr=nil, stdout=nil)
          super(message)

          @stderr = stderr
          @stdout = stdout
        end
      end

      PROCESS_WAIT_TIME = 10

      def self.open_pipe_with_timeout(timeout, *cmd, &block)
        begin
          i, o, e, t, pid = nil

          Timeout.timeout(timeout, ProcessDidNotExitError) do
            i, o, e, t = Open3.popen3(*cmd)
            i.sync = true
            o.sync = true
            e.sync = true
            pid = t.pid
            block.call(i, o, e)

            t.value.exitstatus
          end
        rescue ProcessDidNotExitError => _
          raise ADBCallError, 'Process did not exit'
        ensure
          i.close unless i.nil? || i.closed?
          o.close unless o.nil? || o.closed?
          e.close unless e.nil? || e.closed?

          if pid
            begin
              Process.kill(9, pid)
            rescue Errno::ESRCH => _
              # do nothing
            end
          end

          t.join if t
        end
      end

      def self.open_adb_pipe(*cmd, **options, &block)
        timeout = options.fetch(:timeout, 10)

        open_pipe_with_timeout(timeout, Environment.adb_path, *cmd) do |i, o, e|
          block.call(i, o, e) if block
        end
      end

      DAEMON_STARTED_MESSAGE = "* daemon not running. starting it now on port 5037 *\n* daemon started successfully *\n"

      def self.command(*cmd, **args)
        Logger.debug("ADB Command: #{cmd.join(', ')}")
        Logger.debug("ADB input: #{args[:input]}")
        stderr = nil
        stdout = nil
        exit_code = nil

        input = args[:input]

        begin
          exit_code = open_adb_pipe(*cmd, args) do |i, o, e|
            if input
              input.each do |p_cmd|
                begin
                  i.puts p_cmd
                rescue Errno::EPIPE => err
                  i.close
                  stderr = e.readlines.join
                  stdout = o.readlines.join
                  raise ADBCallError.new(err, stderr, stdout)
                end
              end

              i.close
            end

            unless args.fetch(:no_read, false)
              stderr = e.readlines.join
              stdout = o.readlines.join
            end

            if stdout && stdout.start_with?(DAEMON_STARTED_MESSAGE)
              stdout = stdout[DAEMON_STARTED_MESSAGE.length..-1]
            end
          end
        rescue IOError => e
          raise ADBCallError, e
        end

        if exit_code != 0
          Logger.debug("Adb process exited with #{exit_code}")
          Logger.debug("Error message from ADB: ")
          Logger.debug(stderr)

          raise ADBCallError.new(
                "Adb process exited with #{exit_code}: #{dot_string(stderr.lines.first, 100)}", stderr, stdout)
        end

        stdout
      end

      attr_reader :serial

      def initialize(serial)
        @serial = serial
      end

      def command(*argv, **args)
        cmd = argv.dup

        if serial
          cmd.unshift('-s', serial)
        end

        ADB.command(*cmd, args)
      end

      def shell(shell_cmd, options={})
        input =
            [
                "#{shell_cmd}; echo \"\n$?\"; exit 0"
            ]

        args = options.merge(input: input)

        result = command('shell', args)

        # We get a result like this:
        #
        # [0] "getprop ro.build.version.release; echo \"\r\n",
        # [1] "$?\"; exit 0\r\n",
        # [2] "shell@hammerhead:/ $ getprop ro.build.version.release; echo \"\r\r\n",
        # [3] "> $?\"; exit 0\r\r\n",
        # [4] "4.4\r\n",
        # [5] "\r\n",
        # [6] "0\r\n"
        #
        # out =
        # [4] "4.4\r\n"
        # [5] "\r\n",
        # [6] "0\r\n"
        #
        # command_result =
        # [4] "4.4\r\n"
        # [5] "\r\n",
        #
        # exit_code_s =
        # [6] "0\r\n"

        index = result.lines.index {|line| line.end_with?("; exit 0\r\r\n")}

        if index.nil?
          raise ADBCallError.new('Could not parse output', result)
        end

        # Remove the commands
        out = result.lines[index+1..-1]

        # Get the result from the command
        command_result = out[0..-2].join

        # Get the exit code
        exit_code_s = out[-1]

        unless options[:no_exit_code_check]
          unless exit_code_s.to_i.to_s == exit_code_s.chomp
            raise ADBCallError,
                  "Unable to obtain exit code. Result: '#{exit_code_s}'"
          end

          exit_code = exit_code_s.to_i

          if exit_code != 0
            Logger.debug("Adb shell command exited with #{exit_code}")
            Logger.debug("Error message from ADB: ")
            Logger.debug(command_result)

            raise ADBCallError.new(
                      "Adb shell command exited with #{exit_code}: #{ADB.dot_string(command_result.lines.first, 100)}", command_result)
          end
        end

        command_result
      end

      private

      def self.dot_string(string, length)
        if string.length > length
          "#{string[0, length-3]}..."
        else
          string
        end
      end

      # @!visibility private
      class ProcessDidNotExitError < RuntimeError; end
    end
  end
end
