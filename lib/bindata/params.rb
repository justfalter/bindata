require 'bindata/lazy'
require 'set'

module BinData
  # BinData objects accept parameters when initializing.  AcceptedParameters
  # allow a BinData class to declaratively identify accepted parameters as
  # mandatory, optional, default or mutually exclusive.
  class AcceptedParameters

    def self.invalid_parameter_names
      unless defined? @invalid_names
        @invalid_names = Set.new
        @invalid_names.merge LazyEvaluator.instance_methods.collect {|name| name.to_sym}
        @invalid_names.merge Kernel.methods.collect {|name| name.to_sym}
        @invalid_names.delete :type
      end
      @invalid_names
    end

    def initialize(ancestor_params = nil)
      @mandatory = ancestor_params ? ancestor_params.mandatory : []
      @optional  = ancestor_params ? ancestor_params.optional  : []
      @default   = ancestor_params ? ancestor_params.default   : Hash.new
      @mutually_exclusive = ancestor_params ?
                                     ancestor_params.mutually_exclusive : []
    end

    def mandatory(*args)
      if not args.empty?
        ensure_valid_names(args)
        @mandatory.concat(args.collect { |arg| arg.to_sym })
        @mandatory.uniq!
      end
      @mandatory.dup
    end

    def optional(*args)
      if not args.empty?
        ensure_valid_names(args)
        @optional.concat(args.collect { |arg| arg.to_sym })
        @optional.uniq!
      end
      @optional.dup
    end

    def default(args = {})
      if not args.empty?
        ensure_valid_names(args.keys)
        args.each_pair do |param, value|
          @default[param.to_sym] = value
        end
      end
      @default.dup
    end

    def mutually_exclusive(*args)
      arg1, arg2 = args
      if arg1 != nil && arg2 != nil
        @mutually_exclusive.push([arg1.to_sym, arg2.to_sym])
        @mutually_exclusive.uniq!
      end
      @mutually_exclusive.dup
    end

    def all
      (@mandatory + @optional + @default.keys).uniq
    end

    #---------------
    private

    def ensure_valid_names(names)
      invalid_names = self.class.invalid_parameter_names
      names.each do |name|
        sym_name = name.to_sym
        name = name.to_s
        if invalid_names.include?(sym_name)
          raise NameError.new("Rename parameter '#{name}' " +
                              "as it shadows an existing method.", name)
        end
      end
    end
  end
end
