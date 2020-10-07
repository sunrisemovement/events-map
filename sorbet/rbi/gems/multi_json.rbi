# This file is autogenerated. Do not edit it by hand. Regenerate it with:
#   srb rbi gems

# typed: strict
#
# If you would like to make changes to this file, great! Please create the gem's shim here:
#
#   https://github.com/sorbet/sorbet-typed/new/master?filename=lib/multi_json/all/multi_json.rbi
#
# multi_json-1.14.1

module MultiJson
  def adapter; end
  def adapter=(new_adapter); end
  def cached_options(*arg0); end
  def current_adapter(options = nil); end
  def decode(string, options = nil); end
  def default_adapter; end
  def default_engine; end
  def default_options; end
  def default_options=(value); end
  def dump(object, options = nil); end
  def encode(object, options = nil); end
  def engine; end
  def engine=(new_adapter); end
  def load(string, options = nil); end
  def load_adapter(new_adapter); end
  def load_adapter_from_string_name(name); end
  def reset_cached_options!(*arg0); end
  def use(new_adapter); end
  def with_adapter(new_adapter); end
  def with_engine(new_adapter); end
  extend MultiJson
  include MultiJson::Options
end
module MultiJson::Options
  def default_dump_options; end
  def default_load_options; end
  def dump_options(*args); end
  def dump_options=(options); end
  def get_options(options, *args); end
  def load_options(*args); end
  def load_options=(options); end
end
class MultiJson::Version
  def self.to_s; end
end
class MultiJson::AdapterError < ArgumentError
  def cause; end
  def self.build(original_exception); end
end
class MultiJson::ParseError < StandardError
  def cause; end
  def data; end
  def self.build(original_exception, data); end
end
module MultiJson::OptionsCache
  def fetch(type, key, &block); end
  def reset; end
  def write(cache, key); end
  extend MultiJson::OptionsCache
end
