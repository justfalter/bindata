require 'bindata/io'
require 'bindata/lazy'
require 'bindata/params'
require 'bindata/registry'
require 'bindata/sanitize'

module BinData
  # Error raised when unexpected results occur when reading data from IO.
  class ValidityError < StandardError ; end

  # This is the abstract base class for all data objects.
  #
  # == Parameters
  #
  # Parameters may be provided at initialisation to control the behaviour of
  # an object.  These params are:
  #
  # [<tt>:check_offset</tt>]  Raise an error if the current IO offset doesn't
  #                           meet this criteria.  A boolean return indicates
  #                           success or failure.  Any other return is compared
  #                           to the current offset.  The variable +offset+
  #                           is made available to any lambda assigned to
  #                           this parameter.  This parameter is only checked
  #                           before reading.
  # [<tt>:adjust_offset</tt>] Ensures that the current IO offset is at this
  #                           position before reading.  This is like
  #                           <tt>:check_offset</tt>, except that it will
  #                           adjust the IO offset instead of raising an error.
  class Base

    class << self

      # Instantiates this class and reads from +io+, returning the newly
      # created data object.
      def read(io)
        data = self.new
        data.read(io)
        data
      end

      def mandatory_parameters(*args)
        accepted_parameters.mandatory(*args)
      end

      def optional_parameters(*args)
        accepted_parameters.optional(*args)
      end

      def default_parameters(*args)
        accepted_parameters.default(*args)
      end

      def mutually_exclusive_parameters(*args)
        accepted_parameters.mutually_exclusive(*args)
      end

      alias_method :mandatory_parameter, :mandatory_parameters
      alias_method :optional_parameter, :optional_parameters
      alias_method :default_parameter, :default_parameters

      def accepted_parameters
        unless defined? @accepted_parameters
          ancestor = ancestors[1..-1].find { |cls|
                                        cls.respond_to?(:accepted_parameters)
                                       }
          ancestor_params = ancestor.nil? ? nil : ancestor.accepted_parameters
          @accepted_parameters = AcceptedParameters.new(ancestor_params)
        end
        @accepted_parameters
      end

      def sanitize_parameters!(params, sanitizer) #:nodoc:
      end

      #-------------
      private

      def warn_replacement_parameter(params, bad_key, suggested_key)
        if params.has_parameter?(bad_key)
          warn ":#{bad_key} is not used with #{self}.  " +
               "You probably want to change this to :#{suggested_key}"
        end
      end

      def register(name, class_to_register)
        RegisteredClasses.register(name, class_to_register)
      end
    end

    optional_parameters :check_offset, :adjust_offset
    mutually_exclusive_parameters :check_offset, :adjust_offset

    # Creates a new data object.
    #
    # +params+ is a hash containing symbol keys.  Some params may
    # reference callable objects (methods or procs).  +parent+ is the
    # parent data object (e.g. struct, array, choice) this object resides
    # under.
    def initialize(params = {}, parent = nil)
      @params = Sanitizer.sanitize(params, self.class)
      @parent = parent
    end

    attr_reader :parent

    # Returns the result of evaluating the parameter identified by +key+.
    # +overrides+ is an optional +parameters+ like hash that allow the
    # parameters given at object construction to be overridden.
    # Returns nil if +key+ does not refer to any parameter.
    def eval_parameter(key, overrides = {})
      LazyEvaluator.eval(self, get_parameter(key), overrides)
    end

    # Returns the parameter referenced by +key+.
    # Use this method if you are sure the parameter is not to be evaluated.
    # You most likely want #eval_parameter.
    def get_parameter(key)
      @params[key]
    end

    # Returns whether +key+ exists in the +parameters+ hash.
    def has_parameter?(key)
      @params.has_parameter?(key)
    end

    # Reads data into this data object.
    def read(io)
      io = BinData::IO.new(io) unless BinData::IO === io

      do_read(io)
      done_read
      self
    end

    def do_read(io) #:nodoc:
      check_or_adjust_offset(io)
      clear
      _do_read(io)
    end

    def done_read #:nodoc:
      _done_read
    end
    protected :do_read, :done_read

    # Writes the value for this data to +io+.
    def write(io)
      io = BinData::IO.new(io) unless BinData::IO === io

      do_write(io)
      io.flush
      self
    end

    def do_write(io) #:nodoc:
      _do_write(io)
    end
    protected :do_write

    # Returns the number of bytes it will take to write this data.
    def num_bytes
      do_num_bytes.ceil
    end

    def do_num_bytes #:nodoc:
      _do_num_bytes
    end
    protected :do_num_bytes

    # Assigns the value of +val+ to this data object.  Note that +val+ will
    # always be deep copied to ensure no aliasing problems can occur.
    def assign(val)
      _assign(val)
    end

    # Returns a snapshot of this data object.
    def snapshot
      _snapshot
    end

    # Returns the string representation of this data object.
    def to_binary_s
      io = BinData::IO.create_string_io
      write(io)
      io.rewind
      io.read
    end

    # Return a human readable representation of this data object.
    def inspect
      snapshot.inspect
    end

    # Return a string representing this data object.
    def to_s
      snapshot.to_s
    end

    # Work with Ruby's pretty-printer library.
    def pretty_print(pp) #:nodoc:
      pp.pp(snapshot)
    end

    # Returns a user friendly name of this object for debugging purposes.
    def debug_name
      if parent
        parent.debug_name_of(self)
      else
        "obj"
      end
    end

    # Returns the offset of this object wrt to its most distant ancestor.
    def offset
      if parent
        parent.offset + parent.offset_of(self)
      else
        0
      end
    end

    # Returns the offset of this object wrt to its parent.
    def rel_offset
      if parent
        parent.offset_of(self)
      else
        0
      end
    end

    def ==(other) #:nodoc:
      # double dispatch
      other == snapshot
    end

    #---------------
    private

    def check_or_adjust_offset(io)
      if has_parameter?(:check_offset)
        check_offset(io)
      elsif has_parameter?(:adjust_offset)
        adjust_offset(io)
      end
    end

    def check_offset(io)
      actual_offset = io.offset
      expected = eval_parameter(:check_offset, :offset => actual_offset)

      if not expected
        raise ValidityError, "offset not as expected for #{debug_name}"
      elsif actual_offset != expected and expected != true
        raise ValidityError,
              "offset is '#{actual_offset}' but " +
              "expected '#{expected}' for #{debug_name}"
      end
    end

    def adjust_offset(io)
      actual_offset = io.offset
      expected = eval_parameter(:adjust_offset)
      if actual_offset != expected
        begin
          seek = expected - actual_offset
          io.seekbytes(seek)
          warn "adjusting stream position by #{seek} bytes" if $VERBOSE
        rescue
          raise ValidityError,
                "offset is '#{actual_offset}' but couldn't seek to " +
                "expected '#{expected}' for #{debug_name}"
        end
      end
    end

    ###########################################################################
    # To be implemented by subclasses

    # Resets the internal state to that of a newly created object.
    def clear
      raise NotImplementedError
    end

    # Returns true if the object has not been changed since creation.
    def clear?
      raise NotImplementedError
    end

    # Returns the debug name of +child+.  This only needs to be implemented
    # by objects that contain child objects.
    def debug_name_of(child) #:nodoc:
      debug_name
    end

    # Returns the offset of +child+.  This only needs to be implemented
    # by objects that contain child objects.
    def offset_of(child) #:nodoc:
      0
    end

    # Reads the data for this data object from +io+.
    def _do_read(io)
      raise NotImplementedError
    end

    # Trigger function that is called after #do_read.
    def _done_read
      raise NotImplementedError
    end

    # Writes the value for this data to +io+.
    def _do_write(io)
      raise NotImplementedError
    end

    # Returns the number of bytes it will take to write this data.
    def _do_num_bytes
      raise NotImplementedError
    end

    # Assigns the value of +val+ to this data object.  Note that +val+ will
    # always be deep copied to ensure no aliasing problems can occur.
    def _assign(val)
      raise NotImplementedError
    end

    # Returns a snapshot of this data object.
    def _snapshot
      raise NotImplementedError
    end

    # Set visibility requirements of methods to implement
    public :clear, :clear?, :debug_name_of, :offset_of
    private :_do_read, :_done_read, :_do_write, :_do_num_bytes, :_assign, :_snapshot

    # End To be implemented by subclasses
    ###########################################################################
  end
end
