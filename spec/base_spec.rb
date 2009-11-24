#!/usr/bin/env ruby

require File.expand_path(File.join(File.dirname(__FILE__), "spec_common"))
require 'bindata/base'

class BaseStub < BinData::Base
  # Override to avoid NotImplemented errors
  def clear; end
  def clear?; end
  def _do_read(io) end
  def _done_read; end
  def _do_write(io) end
  def _do_num_bytes; end
  def _assign(x); end
  def _snapshot; end

  expose_methods_for_testing
end

class MockBaseStub < BaseStub
  attr_accessor :mock
  def clear;           mock.clear; end
  def clear?;          mock.clear?; end
  def _do_read(io)     mock._do_read(io); end
  def _done_read;      mock._done_read; end
  def _do_write(io)    mock._do_write(io); end
  def _do_num_bytes;   mock._do_num_bytes; end
  def _assign(x);      mock._assign(x); end
  def _snapshot;       mock._snapshot; end
end

describe BinData::Base, "when subclassing" do
  class SubClassOfBase < BinData::Base
    expose_methods_for_testing
  end

  before(:each) do
    @obj = SubClassOfBase.new
  end

  it "should raise errors on unimplemented methods" do
    lambda { @obj.clear }.should raise_error(NotImplementedError)
    lambda { @obj.clear? }.should raise_error(NotImplementedError)
    lambda { @obj.assign(nil) }.should raise_error(NotImplementedError)
    lambda { @obj._do_read(nil) }.should raise_error(NotImplementedError)
    lambda { @obj._done_read }.should raise_error(NotImplementedError)
    lambda { @obj._do_write(nil) }.should raise_error(NotImplementedError)
    lambda { @obj._do_num_bytes }.should raise_error(NotImplementedError)
    lambda { @obj._snapshot }.should raise_error(NotImplementedError)
  end
end

describe BinData::Base, "with parameters" do
  it "should raise error if parameter has nil value" do
    lambda { BaseStub.new(:a => nil) }.should raise_error(ArgumentError)
  end

  it "should raise error if parameter name is invalid" do
    lambda {
      class InvalidParameterNameBase < BinData::Base
        optional_parameter :eval # i.e. Kernel#eval
      end
    }.should raise_error(NameError)
  end

  it "should convert keys to symbols" do
    obj = BaseStub.new('a' => 3)
    obj.should have_parameter(:a)
    obj.get_parameter(:a).should == 3
  end
end

describe BinData::Base, "with mandatory parameters" do
  class MandatoryBase < BaseStub
    mandatory_parameter :p1
    mandatory_parameter :p2
  end

  it "should ensure that all mandatory parameters are present" do
    params = {:p1 => "a", :p2 => "b" }
    lambda { MandatoryBase.new(params) }.should_not raise_error
  end

  it "should fail if not all mandatory parameters are present" do
    params = {:p1 => "a", :xx => "b" }
    lambda { MandatoryBase.new(params) }.should raise_error(ArgumentError)
  end

  it "should fail if no mandatory parameters are present" do
    lambda { MandatoryBase.new() }.should raise_error(ArgumentError)
  end
end

describe BinData::Base, "with default parameters" do
  class DefaultBase < BaseStub
    default_parameter :p1 => "a"
  end

  it "should use default parameters when not specified" do
    obj = DefaultBase.new
    obj.should have_parameter(:p1)
    obj.eval_parameter(:p1).should == "a"
  end

  it "should be able to override default parameters" do
    obj = DefaultBase.new(:p1 => "b")
    obj.should have_parameter(:p1)
    obj.eval_parameter(:p1).should == "b"
  end
end

describe BinData::Base, "with mutually exclusive parameters" do
  class MutexParamBase < BaseStub
    optional_parameters :p1, :p2
    mutually_exclusive_parameters :p1, :p2
  end

  it "should not fail when neither of those parameters are present" do
    lambda { MutexParamBase.new }.should_not raise_error
  end

  it "should not fail when only one of those parameters is present" do
    lambda { MutexParamBase.new(:p1 => "a") }.should_not raise_error
    lambda { MutexParamBase.new(:p2 => "b") }.should_not raise_error
  end

  it "should fail when both those parameters are present" do
    lambda { MutexParamBase.new(:p1 => "a", :p2 => "b") }.should raise_error(ArgumentError)
  end
end

describe BinData::Base, "with multiple parameters" do
  class WithParamBase < BaseStub
    mandatory_parameter :p1
    optional_parameter  :p2
    default_parameter   :p3 => 3
  end

  it "should identify internally accepted parameters" do
    accepted = WithParamBase.accepted_parameters.all
    accepted.should include(:p1)
    accepted.should include(:p2)
    accepted.should include(:p3)
    accepted.should_not include(:xx)
  end

  it "should evaluate parameters" do
    params = {:p1 => 1, :p2 => 2, :p3 => 3, :p4 => lambda { 4 }}
    obj = WithParamBase.new(params)
    obj.eval_parameter(:p4).should == 4
  end

  it "should return parameters" do
    params = {:p1 => 1, :p2 => 2, :p3 => 3, :p4 => :a}
    obj = WithParamBase.new(params)
    obj.get_parameter(:p4).should == :a
  end

  it "should have parameters" do
    params = {:p1 => 1, :p2 => 2, :p3 => 3, :p4 => 4}
    obj = WithParamBase.new(params)
    obj.should have_parameter(:p4)
  end

  it "should not allow parameters with nil values" do
    lambda { WithParamBase.new(:p1 => 1, :p2 => nil) }.should raise_error(ArgumentError)
  end

  it "should be able to access without evaluating" do
    obj = WithParamBase.new(:p1 => :asym, :p3 => lambda {1 + 2})
    obj.get_parameter(:p1).should == :asym
    obj.get_parameter(:p2).should be_nil
    obj.get_parameter(:p3).should respond_to(:arity)
  end
end

describe BinData::Base, "with :check_offset" do
  class TenByteOffsetBase < BaseStub
    def do_read(io)
      # advance the io position before checking offset
      io.seekbytes(10)
      super(io)
    end
  end

  before(:each) do
    @io = BinData::IO.create_string_io("12345678901234567890")
  end

  it "should fail if offset is incorrect" do
    @io.seek(2)
    obj = TenByteOffsetBase.new(:check_offset => 8)
    lambda { obj.read(@io) }.should raise_error(BinData::ValidityError)
  end

  it "should succeed if offset is correct" do
    @io.seek(3)
    obj = TenByteOffsetBase.new(:check_offset => 10)
    lambda { obj.read(@io) }.should_not raise_error
  end

  it "should fail if :check_offset fails" do
    @io.seek(4)
    obj = TenByteOffsetBase.new(:check_offset => lambda { offset == 11 } )
    lambda { obj.read(@io) }.should raise_error(BinData::ValidityError)
  end

  it "should succeed if :check_offset succeeds" do
    @io.seek(5)
    obj = TenByteOffsetBase.new(:check_offset => lambda { offset == 10 } )
    lambda { obj.read(@io) }.should_not raise_error
  end
end

describe BinData::Base, "with :adjust_offset" do
  class TenByteAdjustingOffsetBase < BaseStub
    def do_read(io)
      # advance the io position before checking offset
      io.seekbytes(10)
      super(io)
    end
  end

  before(:each) do
    @io = BinData::IO.create_string_io("12345678901234567890")
  end

  it "should be mutually exclusive with :check_offset" do
    params = { :check_offset => 8, :adjust_offset => 8 }
    lambda { TenByteAdjustingOffsetBase.new(params) }.should raise_error(ArgumentError)
  end

  it "should adjust if offset is incorrect" do
    @io.seek(2)
    obj = TenByteAdjustingOffsetBase.new(:adjust_offset => 13)
    obj.read(@io)
    @io.pos.should == (2 + 13)
  end

  it "should succeed if offset is correct" do
    @io.seek(3)
    obj = TenByteAdjustingOffsetBase.new(:adjust_offset => 10)
    lambda { obj.read(@io) }.should_not raise_error
    @io.pos.should == (3 + 10)
  end

  it "should fail if cannot adjust offset" do
    @io.seek(3)
    obj = TenByteAdjustingOffsetBase.new(:adjust_offset => -4)
    lambda { obj.read(@io) }.should raise_error(BinData::ValidityError)
  end
end

describe BinData::Base, "as black box" do
  it "should access parent" do
    parent = BaseStub.new
    child = BaseStub.new(nil, parent)
    child.parent.should == parent
  end

  it "should instantiate self for ::read" do
    BaseStub.read("").class.should == BaseStub
  end

  it "should return self for #read" do
    obj = BaseStub.new
    obj.read("").should == obj
  end

  it "should return self for #write" do
    obj = BaseStub.new
    obj.write("").should == obj
  end

  it "should forward #inspect to snapshot" do
    class SnapshotBase < BaseStub
      def snapshot; [1, 2, 3]; end
    end
    obj = SnapshotBase.new
    obj.inspect.should == obj.snapshot.inspect
  end

  it "should forward #to_s to snapshot" do
    class SnapshotBase < BaseStub
      def snapshot; [1, 2, 3]; end
    end
    obj = SnapshotBase.new
    obj.to_s.should == obj.snapshot.to_s
  end

  it "should write the same as to_binary_s" do
    class WriteToSBase < BaseStub
      def _do_write(io) io.writebytes("abc"); end
    end

    obj = WriteToSBase.new
    io = BinData::IO.create_string_io
    obj.write(io)
    io.rewind
    written = io.read
    obj.to_binary_s.should == written
  end
end

describe BinData::Base, "as white box" do
  before(:each) do
    @obj = MockBaseStub.new
    @obj.mock = mock('mock')
  end

  it "should forward read to _do_read" do
    @obj.mock.should_receive(:clear).ordered
    @obj.mock.should_receive(:_do_read).ordered
    @obj.mock.should_receive(:_done_read).ordered
    @obj.read(nil)
  end

  it "should forward write to _do_write" do
    @obj.mock.should_receive(:_do_write)
    @obj.write(nil)
  end

  it "should forward num_bytes to _do_num_bytes" do
    @obj.mock.should_receive(:_do_num_bytes).and_return(42)
    @obj.num_bytes.should == 42
  end

  it "should round up fractional num_bytes" do
    @obj.mock.should_receive(:_do_num_bytes).and_return(42.1)
    @obj.num_bytes.should == 43
  end

  it "should forward snapshot to _snapshot" do
    @obj.mock.should_receive(:_snapshot).and_return("abc")
    @obj.snapshot.should == "abc"
  end
end
