#!/usr/bin/env ruby

require 'mirimiri'
require 'sanitize'
require 'lda-ruby'

module Context
  IndexPaths = {
    :web_en        => '/mnt/disk2/ClueWeb09_English_1_sDocs',
    :web_fr        => '/mnt/disk2/ClueWeb09_French_1_sDocs',
    :web_nospam    => '/mnt/disk1/ClueWeb09_English_1noSpam',
    :gigaword      => '/local/data/GigaWord/index',
    :nyt           => '/local/data/NYT_index',
    :wiki_en       => '/local/data/WikiEn_index',
    :wiki_fr       => '/local/data/WikiFr_index'
  }

  def Context.term_context index_path,query,size,num_page,args={}
    args[:func]   ||= :entropy
    args[:window] ||= 1

    docs     = self.feedback_docs  index_path,query,num_page

    resource = Mirimiri::Document.new docs.join(' ')
    terms    = self.extract_ngrams resource,args[:func].to_sym,args[:window]

    context = "#weight ( #{terms.compact.sort{ |a,b| b[0] <=> a[0]}[0,size].collect { |e| "#{e[0]} #1(#{e[1]})" }.join " "} ) " unless terms.empty?

    context
  end

  def Context.topic_context index_path,query,size,num_page,args={}
    corpus = Lda::Corpus.new

    docs   = self.feedback_docs index_path,query,num_page
    docs.each do |d| 
      doc = Lda::TextDocument.new corpus,d
      corpus.add_document doc
    end

    lda = Lda::Lda.new corpus
    lda.num_topics = num_page/10
    lda.em 'random'
    puts lda.top_words(size)
  end

  private
  def Context.feedback_docs index_path,query,num_page
    query = Indri::IndriQuery.new({:query => query, :count => num_page},"-printDocuments=true -trecFormat=true")
    index = Indri::IndriIndex.new index_path
    idocs = Indri::IndriPrintedDocuments.new(index.runquery(query).force_encoding("ISO-8859-1").encode("UTF-8"))

    docs = idocs.extract_docs.collect { |idoc| Sanitize.clean idoc,:remove_contents => ['script']  }
    docs
  end

  def Context.extract_ngrams resource,func,n
    raw_terms = 1.upto(n).collect      { |i| resource.ngrams(i) }.flatten
    terms     = raw_terms.uniq.collect { |w| [resource.send(func.to_sym,w), w.unaccent] unless w.is_stopword? || w.split.all? { |e| e.length <= 1 } || w.split.all? { |e| e !~ /[a-zA-Z]/ } || w.include?(".") }
    terms
  end

end
