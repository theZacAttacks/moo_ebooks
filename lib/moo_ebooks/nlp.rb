
# frozen_string_literal: true

require 'highscore'
require 'htmlentities'

module Ebooks
  # @private
  module NLP
    # We deliberately limit our punctuation handling to stuff we can do
    # consistently
    # It'll just be a part of another token if we don't split it out, and
    # that's fine
    PUNCTUATION = '.?!,'

    # Lazy-load NLP libraries and resources
    # Some of this stuff is pretty heavy and we don't necessarily need
    # to be using it all of the time

    # Lazily loads an array of stopwords
    # Stopwords are common words that should often be ignored
    # @return [Array<String>]
    def self.stopwords
      @stopwords ||= File.read(File.join(DATA_PATH, 'stopwords.txt')).split
    end

    # Lazily load HTML entity decoder
    # @return [HTMLEntities]
    def self.htmlentities
      @htmlentities ||= HTMLEntities.new
    end

    ### Utility functions

    # Normalize some strange unicode punctuation variants
    # @param text [String]
    # @return [String]
    def self.normalize(text)
      htmlentities.decode(text.tr('“', '"').tr('”', '"').tr('’', "'")
        .gsub('…', '...'))
    end

    # Split text into sentences
    # We use ad hoc approach because fancy libraries do not deal
    # especially well with tweet formatting, and we can fake solving
    # the quote problem during generation
    # @param text [String]
    # @return [Array<String>]
    def self.sentences(text)
      text.split(/\n+|(?<=[.?!])\s+/)
    end

    # Split a sentence into word-level tokens
    # As above, this is ad hoc because tokenization libraries
    # do not behave well wrt. things like emoticons and timestamps
    # @param sentence [String]
    # @return [Array<String>]
    def self.tokenize(sentence)
      regex = /\s+|(?<=[#{PUNCTUATION}]\s)(?=[a-zA-Z])|
        (?<=[a-zA-Z])(?=[#{PUNCTUATION}]+\s)/x
      sentence.split(regex)
    end

    # Use highscore gem to find interesting keywords in a corpus
    # @param text [String]
    # @return [Highscore::Keywords]
    def self.keywords(text)
      # Preprocess to remove stopwords (highscore's blacklist is v. slow)
      text = NLP.tokenize(text).reject { |t| stopword?(t) }.join(' ')

      text = Highscore::Content.new(text)

      text.configure do
        # set :multiplier, 2
        # set :upper_case, 3
        # set :long_words, 2
        # set :long_words_threshold, 15
        # set :vowels, 1                     # => default: 0 = not considered
        # set :consonants, 5                 # => default: 0 = not considered
        # set :ignore_case, true             # => default: false
        set :word_pattern, /(?<!@)(?<=\s)[\p{Word}']+/ # => default: /\w+/
        # set :stemming, true                # => default: false
      end

      text.keywords
    end

    # Builds a proper sentence from a list of tikis
    # @param tikis [Array<Integer>]
    # @param tokens [Array<String>]
    # @return [String]
    def self.reconstruct(tikis, tokens)
      text = ''
      last_token = nil
      tikis.each do |tiki|
        next if tiki == INTERIM
        token = tokens[tiki]
        text += ' ' if last_token && space_between?(last_token, token)
        text += token
        last_token = token
      end
      text
    end

    # Determine if we need to insert a space between two tokens
    # @param token1 [String]
    # @param token2 [String]
    # @return [Boolean]
    def self.space_between?(token1, token2)
      p1 = punctuation?(token1)
      p2 = punctuation?(token2)
      if (p1 && p2) || (!p1 && p2) # "foo?!" || "foo."
        false
      else # "foo rah" || "foo. rah"
        true
      end
    end

    # Is this token comprised of punctuation?
    # @param token [String]
    # @return [Boolean]
    def self.punctuation?(token)
      (token.chars.to_set - PUNCTUATION.chars.to_set).empty?
    end

    # Is this token a stopword?
    # @param token [String]
    # @return [Boolean]
    def self.stopword?(token)
      @stopword_set ||= stopwords.map(&:downcase).to_set
      @stopword_set.include?(token.downcase)
    end

    # Determine if a sample of text contains unmatched brackets or quotes
    # This is one of the more frequent and noticeable failure modes for
    # the generator; we can just tell it to retry
    # @param text [String]
    # @return [Boolean]
    def self.unmatched_enclosers?(text)
      enclosers = ['**', '""', '()', '[]', '``', "''"]
      enclosers.each do |pair|
        starter = Regexp.new('(\W|^)' + Regexp.escape(pair[0]) + '\S')
        ender = Regexp.new('\S' + Regexp.escape(pair[1]) + '(\W|$)')

        opened = 0

        tokenize(text).each do |token|
          opened += 1 if token.match(starter)
          opened -= 1 if token.match(ender)

          return true if opened.negative? # Too many ends!
        end

        return true if opened != 0 # Mismatch somewhere.
      end

      false
    end

    # Determine if ary2 is a subsequence of ary1
    # @param ary1 [Array]
    # @param ary2 [Array]
    # @return [Boolean]
    def self.subseq?(ary1, ary2)
      !ary1.each_index.find do |i|
        ary1[i...i + ary2.length] == ary2
      end.nil?
    end
  end
end
