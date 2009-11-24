module BinData
  # A LazyEvaluator is bound to a data object.  The evaluator will evaluate
  # lambdas in the context of this data object.  These lambdas
  # are those that are passed to data objects as parameters, e.g.:
  #
  #    BinData::String.new(:value => lambda { %w{a test message}.join(" ") })
  #
  # As a shortcut, :foo is the equivalent of lambda { foo }.
  #
  # When evaluating lambdas, unknown methods are resolved in the context of the
  # parent of the bound data object.  Resolution is attempted firstly as keys
  # in #parameters, and secondly as methods in this parent.  This
  # resolution propagates up the chain of parent data objects.
  #
  # An evaluation will recurse until it returns a result that is not
  # a lambda or a symbol.
  #
  # This resolution process makes the lambda easier to read as we just write
  # <tt>field</tt> instead of <tt>obj.field</tt>.
  class LazyEvaluator

    class << self
      # Lazily evaluates +val+ in the context of +obj+, with possibility of
      # +overrides+.
      def eval(obj, val, overrides = {})
        if can_eval?(val)
          env = self.new(obj, overrides)
          env.lazy_eval(val)
        else
          val
        end
      end

      #-------------
      private

      def can_eval?(val)
        val.is_a?(Symbol) or val.respond_to?(:arity)
      end
    end

    # Creates a new evaluator.  All lazy evaluation is performed in the
    # context of +obj+.
    # +overrides+ is an optional +obj.parameters+ like hash.
    def initialize(obj, overrides = {})
      @obj = obj
      @overrides = overrides
    end

    def lazy_eval(val)
      if val.is_a? Symbol
        __send__(val)
      elsif val.respond_to? :arity
        instance_eval(&val)
      else
        val
      end
    end

    # Returns a LazyEvaluator for the parent of this data object.
    def parent
      if @obj.parent
        LazyEvaluator.new(@obj.parent)
      else
        nil
      end
    end

    # Returns the index of this data object inside it's nearest container
    # array.
    def index
      return @overrides[:index] if @overrides.has_key?(:index)

      child = @obj
      parent = @obj.parent
      while parent
        if parent.respond_to?(:find_index_of)
          return parent.find_index_of(child)
        end
        child = parent
        parent = parent.parent
      end
      raise NoMethodError, "no index found"
    end

    def method_missing(symbol, *args)
      return @overrides[symbol] if @overrides.has_key?(symbol)

      if @obj.parent
        eval_symbol_in_parent_context(symbol, args)
      else
        super
      end
    end

    #---------------
    private

    def eval_symbol_in_parent_context(symbol, args)
      result = resolve_symbol_in_parent_context(symbol, args)
      recursively_eval(result, args)
    end

    def resolve_symbol_in_parent_context(symbol, args)
      obj_parent = @obj.parent

      if obj_parent.has_parameter?(symbol)
        result = obj_parent.get_parameter(symbol)
      elsif obj_parent.respond_to?(symbol)
        result = obj_parent.__send__(symbol, *args)
      else
        result = symbol
      end
    end

    def recursively_eval(val, args)
      if val.is_a?(Symbol)
        parent.__send__(val, *args)
      elsif val.respond_to?(:arity)
        parent.instance_eval(&val)
      else
        val
      end
    end
  end
end
