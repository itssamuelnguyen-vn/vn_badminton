require "logger"

# Formats each log line as "[LEVEL] [YYYY-MM-DD HH:MM:SS +0700] message".
# Tags from config.log_tags are inserted before the message by TaggedLogging.
class LogFormatter < Logger::Formatter
  # Asia/Ho_Chi_Minh, which has no daylight saving time.
  UTC_OFFSET = "+07:00"

  def call(severity, time, _progname, msg)
    "[#{severity}] [#{time.getlocal(UTC_OFFSET).strftime('%Y-%m-%d %H:%M:%S %z')}] #{msg2str(msg)}\n"
  end
end
