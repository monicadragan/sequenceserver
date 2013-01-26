module Uniprot
  # If your databases were formatted with the `-parse_seqids` option (the
  # bundled database formatting utility takes care of that automatically),
  # SequenceServer will call `SequenceServer::Blast::Hit.refs` method to
  # include download links for each hit in the search report.
  #
  # By overriding this method, SequenceServer can be customized to link each
  # hit to an external resource.  For example: genome browsers, public
  # databanks (Uniprot, etc.).
  #
  # See `SequenceServer::Blast::Hit` to for parameters available to generate
  # refs.
  #
  # The method should call `super` and `update` the Hash returned with name and
  # link to the resource.  Relative URLs will be automatically prefixed with
  # the base URI on which SequenceServer is mounted.
  #
  # Sequence ids are of format "lcl|ACEP_00015614-RA".  Some are like
  # "gi|340708618" -- beginning with a 'gi'.  You might spot them in your FASTA
  # files.  But they never appear in BLAST+'s HTML output that SequenceServer
  # uses, so you can't link to such sequences.  This might change in a future
  # release.
  #
  # Example: link to Uniprot for a protein sequence.
  #
  # def refs
  #  # I get 'tr|E2C070|E2C070_HARSA' kind of ids when BLASTing against
  #  # Harpegnathos saltator's protein sequences downloaded from Uniprot.
  #  uniprot_id = id.split('|')[1]
  #  super.update 'Uniprot' => "http://www.uniprot.org/uniprot/#{uniprot_id}"
  # end
end

class SequenceServer::Blast::Hit
  include Uniprot
end
