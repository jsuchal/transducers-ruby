require "transducers/version"

module Transducers
  def transduce(transducer, reducer, init=nil , coll)
    transducer.
      apply(Transducers.reducer(init, reducer)).
      reduce(coll)
  end

  module_function :transduce

  module Reducing
    def reduce(inputs)
      return reduce_string(inputs) if String === inputs
      result = init
      inputs.each do |input|
        return result.val if Transducers::Reduced === result
        result = step(result, input)
      end
      result
    end

    def reduce_string(str)
      result = init
      str.each_char do |input|
        return result.val if Transducers::Reduced === result
        result = step(result, input)
      end
      result
    end
  end

  class Reducer
    include Reducing

    attr_reader :init

    def initialize(init, sym=:no_sym, &block)
      @init = init
      @sym = sym
      @block = block
      (class << self; self; end).class_eval do
        if block
          def step(result, input)
            @block.call(result, input)
          end
        else
          def step(result, input)
            result.send(@sym, input)
          end
        end
      end
    end

    def result(result)
      result
    end
  end

  def reducer(init, sym_or_reducer=nil, &block)
    if sym_or_reducer.respond_to?(:step)
      sym_or_reducer
    else
      Reducer.new(init, sym_or_reducer, &block)
    end
  end

  module_function :reducer

  class Reduced
    attr_reader :val
    def initialize(val)
      @val = val
    end
  end

  class BaseReducer
    include Reducing

    def initialize(reducer)
      @reducer = reducer
    end

    def init()
      @reducer.init()
    end

    def result(result)
      @reducer.result(result)
    end
  end

  class BaseTransducer
    def normalize_reducer(reducer_or_init, sym=nil)
      sym ? Transducers.reducer(reducer_or_init, sym) : reducer_or_init
    end

    def apply(reducer_or_init, sym=nil)
      reducer = sym ? Transducers.reducer(reducer_or_init, sym) : reducer_or_init
      wrap(reducer)
    end

  end

  class MappingTransducer < BaseTransducer
    class MappingReducer < BaseReducer
      def initialize(reducer, xform)
        super(reducer)
        @xform = xform
      end

      def step(result, input)
        @reducer.step(result, @xform.xform(input))
      end
    end

    class XForm
      def initialize(block)
        @block = block
      end

      def xform(input)
        @block.call(input)
      end
    end

    def initialize(xform, &block)
      @xform = block ? XForm.new(block) : xform
    end

    def wrap(reducer)
      MappingReducer.new(reducer, @xform)
    end
  end

  def mapping(xform=nil, &block)
    MappingTransducer.new(xform, &block)
  end

  class FilteringTransducer < BaseTransducer
    class FilteringReducer < BaseReducer
      def initialize(reducer, pred)
        super(reducer)
        @pred = pred
      end

      def step(result, input)
        input.send(@pred) ? @reducer.step(result, input) : result
      end
    end

    def initialize(pred)
      @pred = pred
    end

    def wrap(reducer)
      FilteringReducer.new(reducer, @pred)
    end
  end

  def filtering(pred)
    FilteringTransducer.new(pred)
  end

  class TakingTransducer < BaseTransducer
    class TakingReducer < BaseReducer
      def initialize(reducer, n)
        super(reducer)
        @n = n
      end

      def step(result, input)
        @n -= 1
        if @n == -1
          Reduced.new(result)
        else
          @reducer.step(result, input)
        end
      end
    end

    def initialize(n)
      @n = n
    end

    def wrap(reducer)
      TakingReducer.new(reducer, @n)
    end
  end

  def taking(n)
    TakingTransducer.new(n)
  end

  class PreservingReduced
    def apply(reducer)
      @reducer = reducer
    end

    def step(result, input)
      ret = @reducer.step(result, input)
      Reduced === ret ? Reduced.new(ret) : ret
    end
  end

  class CattingTransducer < BaseTransducer
    class CattingReducer < BaseReducer
      def step(result, input)
        Transducers.transduce(PreservingReduced.new, @reducer, result, input)
      end
    end

    def wrap(reducer)
      CattingReducer.new(reducer)
    end
  end

  def cat
    CattingTransducer.new
  end

  def mapcat(f=nil, &b)
    compose(mapping(f, &b), cat)
  end

  class ComposedTransducer < BaseTransducer
    def initialize(*transducers)
      @transducers = transducers
    end

    def wrap(reducer)
      @transducers.reverse.reduce(reducer) {|r,t| t.apply(r)}
    end
  end

  def compose(*transducers)
    ComposedTransducer.new(*transducers)
  end

  module_function :mapping, :filtering, :taking, :cat, :compose, :mapcat
end
