CREATE KEYSPACE IF NOT EXISTS zipkin2
  WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '1'}
  AND durable_writes = false;

CREATE TYPE IF NOT EXISTS zipkin2.endpoint (
    service      text,
    ipv4         inet,
    ipv6         inet,
    port         int,
);

CREATE TYPE IF NOT EXISTS zipkin2.annotation (
    ts bigint,
    v  text,
);

CREATE TABLE IF NOT EXISTS zipkin2.span (
    trace_id            text, // when strictTraceId=false, only contains right-most 16 chars
    ts_uuid             timeuuid,
    id                  text,
    trace_id_high       text, // when strictTraceId=false, contains left-most 16 chars if present
    parent_id           text,
    kind                text,
    span                text, // span.name
    ts                  bigint,
    duration            bigint,
    l_ep                Endpoint,
    l_service           text,
    r_ep                Endpoint,
    annotations         list<frozen<annotation>>,
    tags                map<text,text>,
    shared              boolean,
    debug               boolean,
    annotation_query    text, //-- can't do SASI on set<text>: ░-joined until CASSANDRA-11182
    PRIMARY KEY (trace_id, ts_uuid, id)
)
    WITH CLUSTERING ORDER BY (ts_uuid DESC)
    AND compaction = {'class': 'org.apache.cassandra.db.compaction.TimeWindowCompactionStrategy'}
    AND default_time_to_live =  604800
    AND gc_grace_seconds = 3600
    AND read_repair_chance = 0
    AND dclocal_read_repair_chance = 0.0
    AND speculative_retry = '95percentile'
    AND comment = 'Primary table for holding trace data. annotation_query column is a comma separated string (instead of a set) to permit SASI (CASSANDRA-11182)';


CREATE TABLE IF NOT EXISTS zipkin2.trace_by_service_span (
    service       text,             //-- service name
    span          text,             //-- span name, or blank for queries without span name
    bucket        int,              //-- time bucket, calculated as ts/interval (in microseconds), for some pre-configured interval like 1 day.
    ts            timeuuid,         //-- start timestamp of the span, truncated to millisecond precision
    trace_id      text,             //-- trace ID
    duration      bigint,           //-- span duration, in milliseconds
    PRIMARY KEY ((service, span, bucket), ts)
)
   WITH CLUSTERING ORDER BY (ts DESC)
    AND compaction = {'class': 'org.apache.cassandra.db.compaction.TimeWindowCompactionStrategy'}
    AND default_time_to_live =  259200
    AND gc_grace_seconds = 3600
    AND read_repair_chance = 0
    AND dclocal_read_repair_chance = 0
    AND speculative_retry = '95percentile'
    AND comment = 'Secondary table for looking up a trace by a service, or service and span. span column may be blank (when only looking up by service). bucket column adds time bucketing to the partition key, values are microseconds rounded to a pre-configured interval (typically one day). ts column is start timestamp of the span as time-uuid, truncated to millisecond precision. duration column is span duration, rounded up to tens of milliseconds (or hundredths of seconds)';

CREATE TABLE IF NOT EXISTS zipkin2.span_by_service (
    service text,
    span    text,
    PRIMARY KEY (service, span)
)
    WITH compaction = {'class': 'org.apache.cassandra.db.compaction.LeveledCompactionStrategy', 'unchecked_tombstone_compaction': 'true', 'tombstone_threshold': '0.2'}
    AND caching = {'rows_per_partition': 'ALL'}
    AND default_time_to_live =  259200
    AND gc_grace_seconds = 3600
    AND read_repair_chance = 0
    AND dclocal_read_repair_chance = 0
    AND speculative_retry = '95percentile'
    AND comment = 'Secondary table for looking up span names by a service name.';

CREATE CUSTOM INDEX IF NOT EXISTS ON zipkin2.span (annotation_query) USING 'org.apache.cassandra.index.sasi.SASIIndex'
   WITH OPTIONS = {
    'mode': 'CONTAINS',
    'analyzed': 'true',
    'analyzer_class':'org.apache.cassandra.index.sasi.analyzer.NonTokenizingAnalyzer',
    'case_sensitive': 'false'
   };


CREATE CUSTOM INDEX IF NOT EXISTS ON zipkin2.span (l_service) USING 'org.apache.cassandra.index.sasi.SASIIndex'
   WITH OPTIONS = {'mode': 'PREFIX'};

CREATE CUSTOM INDEX IF NOT EXISTS ON zipkin2.trace_by_service_span (duration) USING 'org.apache.cassandra.index.sasi.SASIIndex'
   WITH OPTIONS = {'mode': 'PREFIX'};


CREATE TABLE IF NOT EXISTS zipkin2.dependency (
    day          date,
    parent       text,
    child        text,
    errors       bigint,
    calls        bigint,
    PRIMARY KEY (day, parent, child)
)
    WITH compaction = {'class': 'org.apache.cassandra.db.compaction.LeveledCompactionStrategy', 'unchecked_tombstone_compaction': 'true', 'tombstone_threshold': '0.2'}
    AND default_time_to_live =  259200
    AND gc_grace_seconds = 3600
    AND read_repair_chance = 0
    AND dclocal_read_repair_chance = 0
    AND comment = 'Holder for each days generation of zipkin2.DependencyLink';
