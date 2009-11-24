require 'bindata/sanitize'
require 'bindata/struct'

module BinData
  # A Record is a declarative wrapper around Struct.
  #
  #    require 'bindata'
  #
  #    class Tuple < BinData::Record
  #      int8  :x
  #      int8  :y
  #      int8  :z
  #    end
  #
  #    class SomeDataType < BinData::Record
  #      hide 'a'
  #
  #      int32le :a
  #      int16le :b
  #      tuple   :s
  #    end
  #
  #    obj = SomeDataType.new
  #    obj.field_names   =># ["b", "s"]
  #
  #
  # == Parameters
  #
  # Parameters may be provided at initialisation to control the behaviour of
  # an object.  These params are:
  #
  # <tt>:fields</tt>::   An array specifying the fields for this struct.
  #                      Each element of the array is of the form [type, name,
  #                      params].  Type is a symbol representing a registered
  #                      type.  Name is the name of this field.  Params is an
  #                      optional hash of parameters to pass to this field
  #                      when instantiating it.
  # <tt>:hide</tt>::     A list of the names of fields that are to be hidden
  #                      from the outside world.  Hidden fields don't appear
  #                      in #snapshot or #field_names but are still accessible
  #                      by name.
  # <tt>:endian</tt>::   Either :little or :big.  This specifies the default
  #                      endian of any numerics in this struct, or in any
  #                      nested data objects.
  class Record < BinData::Struct

    class << self

      def inherited(subclass) #:nodoc:
        # Register the names of all subclasses of this class.
        register(subclass.name, subclass)
      end

      def endian(endian = nil)
        @endian ||= default_endian
        if [:little, :big].include?(endian)
          @endian = endian
        elsif endian != nil
          raise ArgumentError,
                  "unknown value for endian '#{endian}' in #{self}", caller(1)
        end
        @endian
      end

      def hide(*args)
        @hide ||= default_hide
        @hide.concat(args.collect { |name| name.to_s })
        @hide
      end

      def fields #:nodoc:
        @fields ||= default_fields
      end

      def method_missing(symbol, *args) #:nodoc:
        name, params = args

        if name.is_a?(Hash)
          params = name
          name = nil
        end

        type = symbol
        name = name.to_s
        params ||= {}

        append_field(type, name, params)
      end

      def sanitize_parameters!(params, sanitizer) #:nodoc:
        params[:fields] = fields
        params[:endian] = endian unless endian.nil?
        params[:hide]   = hide   unless hide.empty?

        super(params, sanitizer)
      end

      #-------------
      private

      def parent_record
        ancestors[1..-1].find { |cls|
          cls.ancestors[1..-1].include?(BinData::Record)
        }
      end

      def default_endian
        rec = parent_record
        rec ? rec.endian : nil
      end

      def default_hide
        rec = parent_record
        rec ? rec.hide.dup : []
      end

      def default_fields
        rec = parent_record
        if rec
          Sanitizer.new.clone_sanitized_fields(rec.fields)
        else
          Sanitizer.new.create_sanitized_fields
        end
      end

      def append_field(type, name, params)
        ensure_valid_name(name)

        fields.add_field(type, name, params, endian)
      rescue UnknownTypeError => err
        raise TypeError, "unknown type '#{err.message}' for #{self}", caller(2)
      end

      def ensure_valid_name(name)
        if fields.field_names.include?(name)
          raise SyntaxError, "duplicate field '#{name}' in #{self}", caller(3)
        end
        if self.instance_methods.collect { |meth| meth.to_s }.include?(name)
          raise NameError.new("", name),
                "field '#{name}' shadows an existing method in #{self}", caller(3)
        end
        if self::RESERVED.include?(name)
          raise NameError.new("", name),
                "field '#{name}' is a reserved name in #{self}", caller(3)
        end
      end
    end
  end
end
