# encoding: utf-8

# text.rb : Implements PDF text primitives
#
# Copyright May 2008, Gregory Brown. All Rights Reserved.
#
# This is free software. Please see the LICENSE and COPYING files for details.
require "prawn/core/text"
require "prawn/text/box"
require "prawn/text/formatted"
require "zlib"

module Prawn
  module Text

    include Prawn::Core::Text
    include Prawn::Text::Formatted

    # If you want text to flow onto a new page or between columns, this is the
    # method to use. If, instead, if you want to place bounded text outside of
    # the flow of a document (for captions, labels, charts, etc.), use Text::Box
    # or its convenience method text_box.
    # 
    # Draws text on the page. Prawn attempts to wrap the text to fit within your
    # current bounding box (or margin_box if no bounding box is being used).
    # Text will flow onto the next page when it reaches the bottom of the
    # bounding box. Text wrap in Prawn does not re-flow linebreaks, so if you
    # want fully automated text wrapping, be sure to remove newlines before
    # attempting to draw your string.
    #
    #   pdf.text "Will be wrapped when it hits the edge of your bounding box"
    #   pdf.text "This will be centered", :align => :center
    #   pdf.text "This will be right aligned", :align => :right
    #
    # If your font contains kerning pairs data that Prawn can parse, the 
    # text will be kerned by default.  You can disable this feature by passing
    # <tt>:kerning => false</tt>.
    #
    # === Text Positioning Details:
    # 
    # The text is positioned at font.ascender below the baseline,
    # making it easy to use this method within bounding boxes and spans.
    #
    # == Encoding
    #
    # Note that strings passed to this function should be encoded as UTF-8.
    # If you get unexpected characters appearing in your rendered document, 
    # check this.
    #
    # If the current font is a built-in one, although the string must be
    # encoded as UTF-8, only characters that are available in WinAnsi
    # are allowed.
    #
    # If an empty box is rendered to your PDF instead of the character you 
    # wanted it usually means the current font doesn't include that character.
    #
    # == Options (default values marked in [])
    #
    # <tt>:kerning</tt>:: <tt>boolean</tt>. Whether or not to use kerning (if it
    #                     is available with the current font) [true]
    # <tt>:size</tt>:: <tt>number</tt>. The font size to use. [current font
    #                  size]
    # <tt>:style</tt>:: The style to use. The requested style must be part of
    #                   the current font familly. [current style]
    # <tt>:indent_paragraphs</tt>:: <tt>number</tt>. The amount to indent the
    #                               first line of each paragraph. Omit this
    #                               option if you do not want indenting
    # <tt>:align</tt>:: <tt>:left</tt>, <tt>:center</tt>, or <tt>:right</tt>.
    #                   Alignment within the bounding box [:left]
    # <tt>:valign</tt>:: <tt>:top</tt>, <tt>:center</tt>, or <tt>:bottom</tt>.
    #                    Vertical alignment within the bounding box [:top]
    # <tt>:leading</tt>:: <tt>number</tt>. Additional space between lines [0]
    # <tt>:final_gap</tt>:: <tt>boolean</tt>. If true, then the space between
    #                       each line is included below the last line;
    #                       otherwise, document.y is placed just below the
    #                       descender of the last line printed [true]
    #
    # <tt>:unformatted_line_wrap</tt>:: <tt>object</tt>. An object used for
    #                        custom line wrapping on a case by case basis. Note
    #                        that if you want to change wrapping document-wide,
    #                        do pdf.default_unformatted_line_wrap =
    #                        MyLineWrap.new.  Your custom object must have a
    #                        wrap_line method that accepts an <tt>options</tt>
    #                        hash and returns the string from that single line
    #                        that can fit on the line under the conditions
    #                        defined by <tt>options</tt>. If omitted, the line
    #                        wrap object is used. The options hash passed into
    #                        the wrap_object proc includes the following
    #                        options:
    #
    #                        <tt>:width</tt>:: the width available for the
    #                                          current line of text
    #                        <tt>:document</tt>:: the pdf object
    #                        <tt>:kerning</tt>:: boolean
    #                        <tt>:line</tt>:: the line of text to wrap
    #
    #                        The line wrap object should have a <tt>width</tt>
    #                        method that returns the width of the last line
    #                        printed
    #
    # Raises <tt>ArgumentError</tt> if <tt>:at</tt> option included
    #
    def text(string, options={})
      # we modify the options. don't change the user's hash
      options = options.dup
      inspect_options_for_text(options)

      if @indent_paragraphs
        string.split("\n").each do |paragraph|
          options[:skip_encoding] = false
          remaining_text = draw_indented_line(paragraph, options)
          options[:skip_encoding] = true
          if remaining_text == paragraph
            # we were too close to the bottom of the page to print even one line
            @bounding_box.move_past_bottom
            remaining_text = draw_indented_line(paragraph, options)
          end
          remaining_text = fill_text_box(remaining_text, options)
          draw_remaining_text_on_new_pages(remaining_text, options)
        end
      else
        remaining_text = fill_text_box(string, options)
        options[:skip_encoding] = true
        draw_remaining_text_on_new_pages(remaining_text, options)
      end
    end


    # Draws formatted text to the page.
    # Formatted text is comprised of an array of hashes, where each hash defines
    # text and format information. As of the time of writing, the following hash
    # options are supported:
    #
    # <tt>:text</tt> the text to format according to the other hash options
    # <tt>:style</tt> an array of styles to apply to this text. As of now,
    #                 :italic and :bold are supported, with the intention of
    #                 also supporting :underline and :strikethrough
    # <tt>:size</tt> an integer denoting the font size to apply to this text
    # <tt>:font</tt> as yet unsupported
    # <tt>:color</tt> as yet unsupported
    # <tt>:link</tt> as yet unsupported
    #
    # For information on options, see documentation for text(). The only
    # difference in options is that if you want to provide a custom wrap object,
    # the option is :formatted_line_wrap, rather than :unformatted_line_wrap
    #
    # <tt>:formatted_line_wrap</tt>:: <tt>object</tt>. An object used for
    #                       custom line wrapping on a case by case basis. Note
    #                       that if you want to change wrapping document-wide,
    #                       do pdf.default_unformatted_line_wrap =
    #                       MyLineWrap.new.  Your custom object must have a
    #                       wrap_line method that accepts an <tt>options</tt>
    #                       hash and returns the string from that single line
    #                       that can fit on the line under the conditions
    #                       defined by <tt>options</tt>. If omitted, the line
    #                       wrap object is used. The options hash passed into
    #                       the wrap_object proc includes the following
    #                       options:
    #
    #                       <tt>:width</tt>:: the width available for the
    #                                         current line of text
    #                       <tt>:document</tt>:: the pdf object
    #                       <tt>:kerning</tt>:: boolean
    #                       <tt>:format_array_manager</tt>:: a FormatArrayManager
    #                                                        object
    #
    #                        The line wrap object should have a <tt>width</tt>
    #                        method that returns the width of the last line
    #                        printed 
    #
    # Example:
    #   text([{ :text => "hello" },
    #         { :text => "world",
    #           :size => 24,
    #           :style => [:bold, :italic] }])
    #
    def formatted_text(array, options={})
      html_string = Text::Formatted::Parser.to_string(array)
      text(html_string, options)
    end

    # Draws text on the page, beginning at the point specified by the :at option
    # the string is assumed to be pre-formatted to properly fit the page.
    # 
    #   pdf.draw_text "Hello World", :at => [100,100]
    #   pdf.draw_text "Goodbye World", :at => [50,50], :size => 16
    #
    # If your font contains kerning pairs data that Prawn can parse, the 
    # text will be kerned by default.  You can disable this feature by passing
    # <tt>:kerning => false</tt>.
    #
    # === Text Positioning Details:
    #
    # Prawn will position your text by the left-most edge of its baseline, and
    # flow along a single line.  (This means that :align will not work)
    #
    # == Rotation
    #
    # Text can be rotated before it is placed on the canvas by specifying the
    # <tt>:rotate</tt> option with a given angle. Rotation occurs counter-clockwise.
    #
    # == Encoding
    #
    # Note that strings passed to this function should be encoded as UTF-8.
    # If you get unexpected characters appearing in your rendered document, 
    # check this.
    #
    # If the current font is a built-in one, although the string must be
    # encoded as UTF-8, only characters that are available in WinAnsi
    # are allowed.
    #
    # If an empty box is rendered to your PDF instead of the character you 
    # wanted it usually means the current font doesn't include that character.
    #
    # == Options (default values marked in [])
    #
    # <tt>:at</tt>:: <tt>[x, y]</tt>(required). The position at which to start the text
    # <tt>:kerning</tt>:: <tt>boolean</tt>. Whether or not to use kerning (if it
    #                     is available with the current font) [true]
    # <tt>:size</tt>:: <tt>number</tt>. The font size to use. [current font
    #                  size]
    # <tt>:style</tt>:: The style to use. The requested style must be part of
    #                   the current font familly. [current style]
    #
    # <tt>:rotate</tt>:: <tt>number</tt>. The angle to which to rotate text
    #
    # Raises <tt>ArgumentError</tt> if <tt>:at</tt> option omitted
    # Raises <tt>ArgumentError</tt> if <tt>:align</tt> option included
    #
    def draw_text(text, options)
      # we modify the options. don't change the user's hash
      options = options.dup
      inspect_options_for_draw_text(options)
      # dup because normalize_encoding changes the string
      text = text.to_s.dup
      options = @text_options.merge(options)
      save_font do
        process_text_options(options)
        font.normalize_encoding!(text) unless @skip_encoding
        font_size(options[:size]) { draw_text!(text, options) }
      end
    end

    # Gets height of text in PDF points.
    # Same options as text(), except as noted.
    # Not compatible with :indent_paragraphs option
    #
    # Example:
    #   height_of("hello\nworld")
    #
    # Raises <tt>NotImplementedError</tt> if <tt>:indent_paragraphs</tt>
    # option included
    # Raises <tt>Prawn::Errrors::CannotFit</tt> if not wide enough to print
    # any text
    #
    def height_of(string, options={})
      if options[:indent_paragraphs]
        raise NotImplementedError, ":indent_paragraphs option not available" +
          "with height_of"
      end
      process_final_gap_option(options)
      box = Text::Box.new(string,
                          options.merge(:height   => 100000000,
                                        :document => self))
      printed = box.render(:dry_run => true)
      raise Errors::CannotFit if box.text.empty? && !string.empty?

      height = box.height - (box.line_height - box.ascender)
      height += box.line_height + box.leading - box.ascender if @final_gap
      height
    end

    # Gets height of formatted text in PDF points.
    # See documentation for height_of.
    #
    # Example:
    #   height_of_formatted([{ :text => "hello" },
    #                        { :text => "world",
    #                          :size => 24,
    #                          :style => [:bold, :italic] }])
    #
    def height_of_formatted(array, options={})
      if options[:indent_paragraphs]
        raise NotImplementedError, ":indent_paragraphs option not available" +
          "with height_of"
      end
      process_final_gap_option(options)
      box = Text::Formatted::Box.new(array,
                          options.merge(:height   => 100000000,
                                        :document => self))
      printed = box.render(:dry_run => true)
      raise Errors::CannotFit if box.text.empty? && !array.empty?

      height = box.height - (box.line_height - box.ascender)
      height += box.line_height + box.leading - box.ascender if @final_gap
      height
    end

    private

    def draw_remaining_text_on_new_pages(remaining_text, options)
      while remaining_text.length > 0
        @bounding_box.move_past_bottom
        previous_remaining_text = remaining_text
        remaining_text = fill_text_box(remaining_text, options)
        break if remaining_text == previous_remaining_text
      end
    end

    def draw_indented_line(string, options)
      indent(@indent_paragraphs) do
        fill_text_box(string, options.dup.merge(:single_line => true))
      end
    end

    def fill_text_box(text, options)
      bottom = @bounding_box.stretchy? ? @margin_box.absolute_bottom :
                                         @bounding_box.absolute_bottom

      options[:height] = y - bottom
      options[:width] = bounds.width
      options[:at] = [@bounding_box.left_side - @bounding_box.absolute_left,
                      y - @bounding_box.absolute_bottom]

      if @inline_format
        array = Text::Formatted::Parser.to_array(text)
        box = Text::Formatted::Box.new(array, options)
        array = box.render
        remaining_text = Text::Formatted::Parser.to_string(array)
      else
        box = Text::Box.new(text, options)
        remaining_text = box.render
      end

      self.y -= box.height - (box.line_height - box.ascender)
      if @final_gap
        self.y -= box.line_height + box.leading - box.ascender
      end
      remaining_text
    end

    def inspect_options_for_draw_text(options)
      if options[:at].nil?
        raise ArgumentError, "The :at option is required for draw_text"
      elsif options[:align]
        raise ArgumentError, "The :align option does not work with draw_text"
      end
      valid_options = Prawn::Core::Text::VALID_OPTIONS + [:at, :rotate]
      Prawn.verify_options(valid_options, options)
    end

    def inspect_options_for_text(options)
      if options[:at]
        raise ArgumentError, ":at is no longer a valid option with text." +
                             "use draw_text or text_box instead"
      end
      process_final_gap_option(options)
      process_indent_paragraphs_option(options)
      process_inline_format_option(options)
      options[:document] = self
    end

    def process_final_gap_option(options)
      @final_gap = options[:final_gap].nil? || options[:final_gap]
      options.delete(:final_gap)
    end

    def process_indent_paragraphs_option(options)
      @indent_paragraphs = options[:indent_paragraphs]
      options.delete(:indent_paragraphs)
    end

    def process_inline_format_option(options)
      @inline_format = options[:inline_format]
      options.delete(:inline_format)
    end

    def move_text_position(dy)
      bottom = @bounding_box.stretchy? ? @margin_box.absolute_bottom :
                                         @bounding_box.absolute_bottom

      @bounding_box.move_past_bottom if (y - dy) < bottom

      self.y -= dy
    end
  end
end
