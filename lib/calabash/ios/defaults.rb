module Calabash
  module IOS
    def self.setup_defaults!
      # Setup the default application
      Calabash.default_application = Application.default_from_environment

      # Setup the default device
      identifier =
          Device.default_identifier_for_application(Calabash.default_application)

      server = Server.default

      Calabash.default_device = Device.new(identifier, server)
    end
  end
end
