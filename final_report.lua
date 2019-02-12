-- Attempt to dump all latency values, and generally all collected stats data

done = function(summary, latency, requests)
   io.write("-- Final Report ------------------------------\n")

   io.write("Latencies: [")
   -- This horrible loop is quadratic in the number of latencies, because of how wrk's bindings work.
   -- I don't think wrk expects us to ever just dump this array - I can't find a sane way to do it.'
   for counter=1,#latency do
     value, count = latency(counter)
     io.write(string.format("%d,%d, ", value, count))
   end
   io.write("]\n\n")

   io.write("Per-Thread ReqsPerSec: [")
   for counter=1,#requests do
     value, count = requests(counter)
     io.write(string.format("%d,%d, ", value, count))
   end
   io.write("]\n\n")

   io.write("Summary Errors: ")
   io.write(string.format("connect:%d,read:%d,write:%d,status:%d,timeout:%d", summary.errors.connect, summary.errors.read, summary.errors.write, summary.errors.status, summary.errors.timeout))
end
