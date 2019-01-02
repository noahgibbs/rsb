#!/usr/bin/env ruby

require "json"
require "optparse"

cohorts_by = "rvm current,warmup_iters,env-RUBYOPT"
input_glob = "rsb_*.json"

OptionParser.new do |opts|
  opts.banner = "Usage: ruby process.rb [options]"
  opts.on("-c", "--cohorts-by COHORTS", "Comma-separated variables to partition data by, incl. RUBY_VERSION,warmup_iterations,etc.") do |c|
    cohorts_by = c
  end
  opts.on("-i", "--input-glob GLOB", "File pattern to match on (default #{input_glob})") do |s|
    input_glob = s
  end
end.parse!

OUTPUT_FILE = "process_output.json"

cohort_indices = cohorts_by.strip.split(",")

req_time_by_cohort = {}
throughput_by_cohort = {}

INPUT_FILES = Dir[input_glob]

process_output = {
  cohort_indices: cohort_indices,
  input_files: INPUT_FILES,
  #req_time_by_cohort: req_time_by_cohort,
  throughput_by_cohort: throughput_by_cohort,
  startup_by_cohort: startup_by_cohort,
  processed: {
    :cohort => {},
  },
}

INPUT_FILES.each do |f|
  begin
    d = JSON.load File.read(f)
  rescue JSON::ParserError
    raise "Error parsing JSON in file: #{f.inspect}"
  end

  # Assign a cohort to these samples
  cohort_parts = cohort_indices.map do |cohort_elt|
    raise "Unexpected file format for file #{f.inspect}!" unless d && d["settings"] && d["environment"]
    item = nil
    if d["settings"].has_key?(cohort_elt)
      item = d["settings"][cohort_elt]
    elsif d["environment"].has_key?(cohort_elt)
      item = d["environment"][cohort_elt]
    else
      raise "Can't find setting or environment object #{cohort_elt}!"
    end
    item
  end
  cohort = cohort_parts.join(",")

  # Reject incorrect versions of data format
  if d["version"] != 1
    raise "Unrecognized data version #{d["version"].inspect} in JSON file #{f.inspect}!"
  end

  duration = d["requests"]["max_starttime"] - d["requests"]["min_starttime"]
  req_time_by_cohort[cohort] ||= []
  req_time_by_cohort[cohort].concat d["requests"]["benchmark"]

  throughput_by_cohort[cohort] ||= []
  throughput_by_cohort[cohort].push (d["requests"]["benchmark"].size / duration)
end

# TODO: replace all this bespoke logic with descriptive_statistics gem

def percentile(list, pct)
  len = list.length
  how_far = pct * 0.01 * (len - 1)
  prev_item = how_far.to_i
  return list[prev_item] if prev_item >= len - 1
  return list[0] if prev_item < 0

  linear_combination = how_far - prev_item
  list[prev_item] + (list[prev_item + 1] - list[prev_item]) * linear_combination
end

def array_mean(arr)
  return nil if arr.empty?
  arr.inject(0.0, &:+) / arr.size
end

# Calculate variance based on the Wikipedia article of algorithms for variance.
# https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance
# Includes Bessel's correction.
def array_variance(arr)
  n = arr.size
  return nil if arr.empty? || n < 2

  ex = ex2 = 0
  arr.each do |x|
    diff = x - arr[0]
    ex += diff
    ex2 += diff * diff
  end

  (ex2 - (ex * ex) / arr.size) / (arr.size - 1)
end

req_time_by_cohort.keys.sort.each do |cohort|
  data = req_time_by_cohort[cohort]
  data.sort! # Sort request times lowest-to-highest for use with percentile()
  throughputs = throughput_by_cohort[cohort].sort

  cohort_printable = cohort_indices.zip(cohort.split(",")).map { |a, b| "#{a}: #{b}" }.join(", ")
  print "=====\nCohort: #{cohort_printable}, # of data points: #{data.size} http requests\n"
  process_output[:processed][:cohort][cohort] = {
    data_points: data.size,
    request_percentiles: {},
    throughputs: throughputs,
  }
  print "--\n  Request completion times:\n"
  (0..100).each do |p|
    process_output[:processed][:cohort][cohort][:request_percentiles][p.to_s] = percentile(data, p)
    print "  #{"%2d" % p}%ile: #{percentile(data, p)}\n"
  end

  print "--\n  Throughput in reqs/sec for each full run:\n"
  print "  Mean: #{array_mean(throughputs).inspect} Median: #{percentile(throughputs, 50).inspect} Variance: #{array_variance(throughputs).inspect}\n"
  process_output[:processed][:cohort][cohort][:throughput_mean] = array_mean(throughputs)
  process_output[:processed][:cohort][cohort][:throughput_median] = percentile(throughputs, 50)
  process_output[:processed][:cohort][cohort][:throughput_variance] = array_variance(throughputs)
  print "  #{throughputs.inspect}\n\n"
end

print "******************\n"

File.open(OUTPUT_FILE, "w") do |f|
  f.print JSON.pretty_generate(process_output)
end
