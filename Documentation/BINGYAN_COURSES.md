# Bingyan course schedule import

Mikansei reads the user's own daily schedule with the documented, read-only
schedule:self:read permission. The native request is:

    GET https://open-api.bingyan.net/v1/schedule/days
    Authorization: Bearer <personal API Key>

The public setup guide is
https://github.com/BingyanStudio/open-bingyan-docs/blob/main/quickstart.mdx
and the platform is https://open.bingyan.net.

The user creates the key in the Bingyan Open Platform while signed in with
their Hustoday account. The app asks for the key only when the user chooses to
read a schedule, then stores a successfully used key in the device Keychain as
non-synchronizable, ThisDeviceOnly data. The key is not written to Mikansei's
archive or cloud sync. Requests use an ephemeral URL session and disable local
response caching. The CLI's saved authorization is separate from Mikansei.

The request accepts from and to dates in YYYY-MM-DD format using
Asia/Shanghai and is limited to 200 days. period_table is optional and accepts
winter, summer, or cyber; leaving it automatic lets the API choose from the
date.

The importer consumes the public { "days": [...] } shape. Lessons require
course, start_period, and end_period; start_time and end_time are optional
HH:MM values. Events require name, date, and period, and their time values are
optional. Only records with valid, explicit start and end times become dated
Mikansei schedules. The importer never infers clock times from a period
number. It reports and skips records with missing or invalid times.

The preview shows the concrete dates and times before saving. Course rows also
become one-date Course records so the existing after-class assignment prompt
can continue to work. Users can enable or disable those prompts and optional
schedule-start notifications before confirming.

Each imported schedule has a deterministic identity derived from its term (or
period table), date, item kind, course/event name, and source period data.
Repeated imports skip an existing identity and preserve the existing entry.
The API does not expose a server item ID, so imports are snapshots: later
changes in Hustoday do not automatically replace or remove Mikansei entries.

The JSON file importer accepts the same daily response shape for a locally
exported schedule. ICS and CSV course imports, and a newly created manual
course, can also be optionally expanded into dated schedule entries. Their
entries use stable content-based identities as well.
