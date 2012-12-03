# Rudimentary help system. Worth exploring further, though I am not sure how much access to the
# rest of the sytem plugins should be allowed. Should they only be allowed to operate in their own
# sandbox, or reach into the list of registered plugins like this one does?

class Help < CampfireBot::Plugin
  on_command 'help', :help

  def help(msg)
    commands = CampfireBot::Plugin.registered_commands.map \
        { |command| command.matcher.to_s + " " }
    msg.speak("To address me, type \"#{bot.config['nickname']},\" " +
        "(minding the comma) followed by a command, or just " +
        "!command. Available commands: ")
    msg.paste(commands.to_s)
    msg.speak("More detail can be found at " +
        "http://wiki.domain.com/confluence/display/Campfire-bot")
  end
end
