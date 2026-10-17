# Rails wraps fields with errors in <div class="field_with_errors">, which breaks form layouts.
# Mark the field itself with aria-invalid instead; the .form-input class styles it red.
Rails.application.config.action_view.field_error_proc = proc do |html_tag, _instance|
  if html_tag.start_with?("<input", "<select", "<textarea")
    html_tag.sub(/\A<(\w+)/, '<\1 aria-invalid="true"').html_safe
  else
    html_tag
  end
end
