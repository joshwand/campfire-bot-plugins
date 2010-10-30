require "#{BOT_ROOT}/vendor/escape/escape"

class Fun < CampfireBot::Plugin
  on_command    'figlet', :figlet
  
  def figlet(msg)
    output = `#{Escape.shell_command(['figlet', '--', msg[:message]])}`
    msg.paste output
  end
end