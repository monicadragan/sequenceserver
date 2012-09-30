require 'sequenceserver/database'

module SequenceServer
  module Helpers
    module SystemHelpers
      private

      # check if the given command exists and is executable
      # returns True if all is good.
      def command?(command)
        system("which #{command} > /dev/null 2>&1")
      end

      # Returns true if the database name appears to be a multi-part database name.
      #
      # e.g.
      # /home/ben/pd.ben/sequenceserver/db/nr.00 => yes
      # /home/ben/pd.ben/sequenceserver/db/nr => no
      # /home/ben/pd.ben/sequenceserver/db/img3.5.finished.faa.01 => yes
      def multipart_database_name?(db_name)
        !(db_name.match(/.+\/\S+\d{2}$/).nil?)
      end
    end

    def self.included(klass)
      klass.extend SystemHelpers
    end
  end
end
