#!/usr/bin/env ruby
# Cerca definizioni di OpenFoodFactsClient nel progetto

Dir.glob("**/*.rb").each do |file|
  File.foreach(file).with_index(1) do |line, num|
    if line =~ /\b(class|module)\s+OpenFoodFactsClient\b/
      puts "#{file}:#{num} -> #{line.strip}"
    end
  end
end
