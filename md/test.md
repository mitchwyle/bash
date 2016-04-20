# Monitoring

We monitor our systems to increase their reliability.  A reliable
systems is available and the service it provides is not attenuated.

## Availability

Availability is proportional to the time between failures divided by the time to
mitigate failures.  Mitigation includes the sum of the times to detect,
communicate, alert, respond, diagnos, fix, deploy, and verify.  In more
detail:

A service is *available* if it correctly responds
to a request within a maximum time.

- A service is unavailable if it responds more slowly than the threshold maximum
  time.
- A service is unavailable if a response contains “old,” “default,” or “fall-back”
data that exceeds a maximum age threshold.
- A service is unavailable if it responds with an error.
- A service is unavailable if it does not respond.
- A service is unavailable if any underlying system or service upon which the
service depends is unavailable.

- A service is attenuated if it responds with incorrect or incomplete data
- A service is attenuated if it responds with old, “default,” or “fall-back” data
- A service is attenuated if one or more of its subsystems or redundant systems
are unavailable.
- A service is attenuated if its capacity has been exceeded and admission control
is in effect.
- A service is attenuated if its nominal duty cycle is not achieved over some time
interval
- A service is attenuated if its availability target over some time interval is
below the target level
- A service is attenuated if any of the 7-number-summary percentile latencies
(0th, 25th, 50th, 75th, 99th, 100th) is above the characterized target levels
but less than a max threshold

And more formally:

![formal service availability][slide3]
[slide3]:img/Slide3.PNG

## Mitigation or Repair?

- Time to Mitigate (TTM) is time to restore service
- Time to Repair (TTR) is time to ship a bug fix (diagnose, code, test,
release) that prevents future service outages from this type of software
defect
- Service availability can be very high even with high failure rates –
Hardware load balancers that automatically fail-over, high-availability
redundant systems, recovery-oriented computing increase availability

Time between failures is service uptime.

A “Duty Cycle” is the mean between failures (MTBF) divided by mean time to repair (MTTR).
“Average”  (mean) is misleading and should not be used.

![tbf and ttr diagram][slide6]
[slide6]:img/Slide6.PNG


## Why Monitor?


