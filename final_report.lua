-- Attempt to dump all latency values, and generally all collected stats data

done = function(summary, latency, requests)
   io.write("-- Final Report ------------------------------\n")

   io.write("Latencies: [")
   -- This horrible loop is quadratic in the number of latencies, because of how wrk's bindings work.
   -- I don't think wrk expects us to ever just dump this array - I can't find a sane way to do it.'
   for counter=1,#latency do
     io.write(string.format("%d,%g, ", counter, latency(counter)))
   end
   io.write("]\n\n")

   io.write("Per-Thread Reqs/Sec: [")
   for counter=1,#requests do
     io.write(string.format("%d,%g, ", counter, requests(counter)))
   end
   io.write("]\n\n")

   io.write("Summary Errors: ")
   io.write(string.format("connect:%d,read:%d,write:%d,status:%d,timeout:%d", summary.errors.connect, summary.errors.read, summary.errors.write, summary.errors.status, summary.errors.timeout))
end
