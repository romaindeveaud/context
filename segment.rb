require 'rubygems'
require 'memoize'
require 'google_ngram'

# This code based on Peter Novig's chapter on "Natural Language Corpus Data" in
# Beautiful Data. 

include Memoize

$bi_model = Google::Ngram.new(:path => '/local/data/web_5gram/data/2gms')
$uni_model = Google::Ngram.new(:path => '/local/data/web_5gram/data/1gms')

$magic_pr =  -16.142698764157398 # twice as uncommon as "kraig" last word in Bing 100k list

# Returns all the splits of a string up to a given length
def splits(text,max_len=text.size)
  Range.new(0,[text.size,max_len].min-1).map{|i| [text[0..i],text[i+1..-1]]}
end

# This keeps just those splits whose first item is above the magic unigram
# log probability
def reasonable_splits(text,max_len=text.size)
  splits(text,max_len).find_all{|pre,suf| Pr(pre)>=$magic_pr}
end

# Get the unigram log probability of a token
def Pr(str)
  Math.log $uni_model.cp(str)
end 

# Get the conditional probability of a word, given a prior
def cPw(word, prev)
  r = $bi_model.cp([prev,word].join(' '))/$uni_model.cp(prev)
  r = r.nan? ? 0.0 : r
  Math.log(r)
end

# combine data
def combine(pfirst, first, pr)
  prem, rem = pr
  return [pfirst+prem, [first]+rem]
end

# segment a text, assuming it is at the beginning of a sentence
# return a pair: the log probability, and the most probable segmentation
def segment2(text, prev="<s>")
#  puts "segment2: #{text.inspect} prev: #{prev}"
  return [0.0,[]] if (!text or text.size==0)
#  reasonable_splits(text).map{|first,rem| combine(cPw(first,prev), first, segment2(rem, first))}.max
  r = reasonable_splits(text).map{|first,rem| combine(cPw(first,prev), first, segment2(rem, first))}
  r.max
end

# just return the best segmentation
def segment(text)
  segment2(text)[1]
end

# We want to memoize a lot of things.
memoize :splits
memoize :reasonable_splits
memoize :Pr 
memoize :cPw 
memoize :segment2 

p segment "CardinalKeithOBrien"
# These are some Twitter hash tags which I segmented.
#  > segment("bpcares")
#  => ["bp", "cares"] 
#  > segment("Twitter")
#  => ["Twitter"] 
#  > segment("writers")
#  => ["writers"] 
#  > segment("iamwriting")
#  => ["i", "am", "writing"] 
#  > segment("backchannel")
#  => ["back", "channel"] 
#  > segment("tcot")
#  => ["tcot"] 
#  => ["vacation", "fall", "out"] 


