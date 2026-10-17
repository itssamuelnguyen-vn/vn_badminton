# Normalizes Vietnamese phone numbers to E.164: +84xxxxxxxxx
#   "0901 234 567"  -> "+84901234567"
#   "84901234567"   -> "+84901234567"
#   "+84 90-123-4567" -> "+84901234567"
module PhoneNumber
  FORMAT = /\A\+84\d{9}\z/

  def self.normalize(raw)
    return nil if raw.blank?

    digits = raw.to_s.gsub(/[^\d+]/, "")
    case digits
    when /\A0(\d{9})\z/    then "+84#{$1}"
    when /\A84(\d{9})\z/   then "+84#{$1}"
    when /\A\+84(\d{9})\z/ then "+84#{$1}"
    else digits # leave as-is so validation reports a format error
    end
  end
end
