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

  # For URLs: "+84901234567" -> "0901234567".
  def self.local_digits(phone)
    phone.to_s.match?(FORMAT) ? "0#{phone[3, 9]}" : phone
  end

  # For display: "+84901234567" -> "0901 234 567". Anything else is returned unchanged.
  def self.to_local(phone)
    return phone unless phone.to_s.match?(FORMAT)

    "0#{phone[3, 9]}".sub(/\A(\d{4})(\d{3})(\d{3})\z/, '\1 \2 \3')
  end
end
