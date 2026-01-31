SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: timescaledb; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS timescaledb WITH SCHEMA public;


--
-- Name: EXTENSION timescaledb; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION timescaledb IS 'Enables scalable inserts and complex queries for time-series data (Community Edition)';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: _compressed_hypertable_2; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._compressed_hypertable_2 (
);


--
-- Name: bmc_sensor_readings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bmc_sensor_readings (
    node_id bigint NOT NULL,
    sensor_type character varying NOT NULL,
    sensor_name character varying NOT NULL,
    value double precision NOT NULL,
    unit character varying NOT NULL,
    status character varying,
    recorded_at timestamp with time zone NOT NULL
);


--
-- Name: _direct_view_4; Type: VIEW; Schema: _timescaledb_internal; Owner: -
--

CREATE VIEW _timescaledb_internal._direct_view_4 AS
 SELECT node_id,
    sensor_type,
    sensor_name,
    public.time_bucket('01:00:00'::interval, recorded_at) AS bucket,
    avg(value) AS avg_value,
    min(value) AS min_value,
    max(value) AS max_value,
    unit
   FROM public.bmc_sensor_readings
  GROUP BY node_id, sensor_type, sensor_name, (public.time_bucket('01:00:00'::interval, recorded_at)), unit;


--
-- Name: _materialized_hypertable_4; Type: TABLE; Schema: _timescaledb_internal; Owner: -
--

CREATE TABLE _timescaledb_internal._materialized_hypertable_4 (
    node_id bigint,
    sensor_type character varying,
    sensor_name character varying,
    bucket timestamp with time zone NOT NULL,
    avg_value double precision,
    min_value double precision,
    max_value double precision,
    unit character varying
);


--
-- Name: _partial_view_4; Type: VIEW; Schema: _timescaledb_internal; Owner: -
--

CREATE VIEW _timescaledb_internal._partial_view_4 AS
 SELECT node_id,
    sensor_type,
    sensor_name,
    public.time_bucket('01:00:00'::interval, recorded_at) AS bucket,
    avg(value) AS avg_value,
    min(value) AS min_value,
    max(value) AS max_value,
    unit
   FROM public.bmc_sensor_readings
  GROUP BY node_id, sensor_type, sensor_name, (public.time_bucket('01:00:00'::interval, recorded_at)), unit;


--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id bigint NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    record_id bigint NOT NULL,
    blob_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_attachments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_attachments_id_seq OWNED BY public.active_storage_attachments.id;


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id bigint NOT NULL,
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    service_name character varying NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_blobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_blobs_id_seq OWNED BY public.active_storage_blobs.id;


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id bigint NOT NULL,
    blob_id bigint NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_variant_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_variant_records_id_seq OWNED BY public.active_storage_variant_records.id;


--
-- Name: api_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_keys (
    id bigint NOT NULL,
    name character varying NOT NULL,
    token character varying NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    last_used_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    bmc_access boolean DEFAULT false NOT NULL
);


--
-- Name: api_keys_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.api_keys_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: api_keys_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.api_keys_id_seq OWNED BY public.api_keys.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: artifact_indices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.artifact_indices (
    id bigint NOT NULL,
    benchmark_run_id bigint NOT NULL,
    path character varying,
    file_type character varying,
    size bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    stored_path character varying
);


--
-- Name: artifact_indices_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.artifact_indices_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: artifact_indices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.artifact_indices_id_seq OWNED BY public.artifact_indices.id;


--
-- Name: benchmark_recipes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.benchmark_recipes (
    id bigint NOT NULL,
    name character varying(100) NOT NULL,
    version character varying(50) NOT NULL,
    default_profile jsonb DEFAULT '{}'::jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    slug character varying,
    command character varying,
    description text,
    timeout_seconds integer DEFAULT 3600,
    status integer DEFAULT 0 NOT NULL
);


--
-- Name: benchmark_recipes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.benchmark_recipes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: benchmark_recipes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.benchmark_recipes_id_seq OWNED BY public.benchmark_recipes.id;


--
-- Name: benchmark_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.benchmark_runs (
    id bigint NOT NULL,
    node_id bigint NOT NULL,
    benchmark_recipe_id bigint NOT NULL,
    started_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    status integer DEFAULT 0 NOT NULL,
    metrics jsonb DEFAULT '{}'::jsonb,
    error_message text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    log_path character varying,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    log_content text,
    arguments jsonb DEFAULT '{}'::jsonb,
    current_phase character varying
);


--
-- Name: benchmark_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.benchmark_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: benchmark_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.benchmark_runs_id_seq OWNED BY public.benchmark_runs.id;


--
-- Name: bmc_credentials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bmc_credentials (
    id bigint NOT NULL,
    node_id bigint,
    bmc_address character varying NOT NULL,
    username character varying NOT NULL,
    password character varying NOT NULL,
    protocol integer DEFAULT 0,
    port integer,
    verify_ssl boolean DEFAULT true,
    is_global_default boolean DEFAULT false,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    collection_interval integer DEFAULT 5
);


--
-- Name: bmc_credentials_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bmc_credentials_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bmc_credentials_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bmc_credentials_id_seq OWNED BY public.bmc_credentials.id;


--
-- Name: bmc_inventories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bmc_inventories (
    id bigint NOT NULL,
    node_id bigint NOT NULL,
    processors jsonb DEFAULT '[]'::jsonb,
    memory jsonb DEFAULT '[]'::jsonb,
    storage jsonb DEFAULT '[]'::jsonb,
    network jsonb DEFAULT '[]'::jsonb,
    infiniband jsonb DEFAULT '[]'::jsonb,
    bios jsonb DEFAULT '{}'::jsonb,
    bmc_info jsonb DEFAULT '{}'::jsonb,
    collection_method integer,
    captured_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: bmc_inventories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bmc_inventories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bmc_inventories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bmc_inventories_id_seq OWNED BY public.bmc_inventories.id;


--
-- Name: bmc_sensor_readings_hourly; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.bmc_sensor_readings_hourly AS
 SELECT node_id,
    sensor_type,
    sensor_name,
    bucket,
    avg_value,
    min_value,
    max_value,
    unit
   FROM _timescaledb_internal._materialized_hypertable_4;


--
-- Name: inventory_discrepancies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_discrepancies (
    id bigint NOT NULL,
    node_id bigint NOT NULL,
    field_path character varying NOT NULL,
    inband_value character varying,
    bmc_value character varying,
    severity integer DEFAULT 0,
    resolved_at timestamp(6) without time zone,
    resolution_note text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: inventory_discrepancies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.inventory_discrepancies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: inventory_discrepancies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.inventory_discrepancies_id_seq OWNED BY public.inventory_discrepancies.id;


--
-- Name: mlc_baselines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mlc_baselines (
    id bigint NOT NULL,
    node_id bigint NOT NULL,
    benchmark_run_id bigint NOT NULL,
    metric_type character varying NOT NULL,
    value double precision NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: mlc_baselines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.mlc_baselines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mlc_baselines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.mlc_baselines_id_seq OWNED BY public.mlc_baselines.id;


--
-- Name: mlc_installation_nodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mlc_installation_nodes (
    id bigint NOT NULL,
    mlc_installation_id bigint NOT NULL,
    node_id bigint NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    step_current integer DEFAULT 0,
    step_total integer DEFAULT 7,
    step_name character varying,
    error_message text,
    started_at timestamp(6) without time zone,
    completed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: mlc_installation_nodes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.mlc_installation_nodes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mlc_installation_nodes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.mlc_installation_nodes_id_seq OWNED BY public.mlc_installation_nodes.id;


--
-- Name: mlc_installations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mlc_installations (
    id bigint NOT NULL,
    uuid character varying NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    source_type integer DEFAULT 0 NOT NULL,
    source_path character varying,
    binary_path character varying,
    checksum_algorithm character varying,
    checksum_value character varying,
    checksum_verified boolean DEFAULT false,
    detected_version character varying,
    install_dir character varying DEFAULT '/opt/qct/utils/qis/software'::character varying,
    module_dir character varying DEFAULT '/opt/qct/utils/qis/modulefiles'::character varying,
    failure_mode integer DEFAULT 0 NOT NULL,
    created_by_id bigint,
    started_at timestamp(6) without time zone,
    completed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: mlc_installations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.mlc_installations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mlc_installations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.mlc_installations_id_seq OWNED BY public.mlc_installations.id;


--
-- Name: node_states; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.node_states (
    id bigint NOT NULL,
    node_id bigint NOT NULL,
    cpu_info jsonb DEFAULT '{}'::jsonb,
    mem_info jsonb DEFAULT '{}'::jsonb,
    disk_info jsonb DEFAULT '[]'::jsonb,
    net_info jsonb DEFAULT '[]'::jsonb,
    captured_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    host_info jsonb DEFAULT '{}'::jsonb,
    dmi_info jsonb DEFAULT '{}'::jsonb,
    network_inventory jsonb
);


--
-- Name: node_states_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.node_states_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: node_states_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.node_states_id_seq OWNED BY public.node_states.id;


--
-- Name: nodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.nodes (
    id bigint NOT NULL,
    hostname character varying(255) NOT NULL,
    ip character varying,
    role integer DEFAULT 0 NOT NULL,
    arch character varying,
    source integer DEFAULT 0 NOT NULL,
    last_seen_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    uuid character varying,
    api_token character varying,
    api_key_id bigint,
    rack_id bigint,
    rack_position integer,
    rack_height integer DEFAULT 1,
    rack_face integer DEFAULT 0,
    server_product_id bigint,
    salt_status integer DEFAULT 0 NOT NULL,
    bmc_address character varying
);


--
-- Name: nodes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.nodes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: nodes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.nodes_id_seq OWNED BY public.nodes.id;


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    notification_type character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    title character varying NOT NULL,
    message character varying,
    resource_type character varying,
    resource_id bigint,
    metadata jsonb DEFAULT '{}'::jsonb,
    read boolean DEFAULT false,
    archived boolean DEFAULT false,
    started_at timestamp(6) without time zone,
    completed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: notifications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notifications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notifications_id_seq OWNED BY public.notifications.id;


--
-- Name: profiling_artifacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiling_artifacts (
    id bigint NOT NULL,
    profiling_run_id bigint NOT NULL,
    filename character varying NOT NULL,
    file_type character varying,
    file_path character varying,
    file_size bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: profiling_artifacts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.profiling_artifacts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: profiling_artifacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.profiling_artifacts_id_seq OWNED BY public.profiling_artifacts.id;


--
-- Name: profiling_recipes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiling_recipes (
    id bigint NOT NULL,
    name character varying(100) NOT NULL,
    slug character varying NOT NULL,
    description text,
    tool character varying DEFAULT 'perfspect'::character varying NOT NULL,
    subcommand character varying NOT NULL,
    module_name character varying DEFAULT 'perfspect/3.13.0'::character varying NOT NULL,
    default_options jsonb DEFAULT '{}'::jsonb,
    timeout_seconds integer DEFAULT 300,
    status integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: profiling_recipes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.profiling_recipes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: profiling_recipes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.profiling_recipes_id_seq OWNED BY public.profiling_recipes.id;


--
-- Name: profiling_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiling_runs (
    id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    node_id bigint NOT NULL,
    profiling_recipe_id bigint,
    user_id bigint,
    status integer DEFAULT 0 NOT NULL,
    subcommand character varying NOT NULL,
    options jsonb DEFAULT '{}'::jsonb,
    metrics jsonb DEFAULT '{}'::jsonb,
    started_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    log_content text,
    error_message text,
    artifact_path character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: profiling_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.profiling_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: profiling_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.profiling_runs_id_seq OWNED BY public.profiling_runs.id;


--
-- Name: racks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.racks (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    facility_id character varying(255),
    asset_tag character varying(255),
    u_height integer DEFAULT 42 NOT NULL,
    width_mm integer,
    depth_mm integer,
    max_weight_kg integer,
    status integer DEFAULT 0 NOT NULL,
    desc_units boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    room_id bigint NOT NULL
);


--
-- Name: racks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.racks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: racks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.racks_id_seq OWNED BY public.racks.id;


--
-- Name: rooms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rooms (
    id bigint NOT NULL,
    site_id bigint NOT NULL,
    name character varying NOT NULL,
    description text,
    floor_area_sqm numeric(10,2),
    power_capacity_kw numeric(10,2),
    cooling_capacity_kw numeric(10,2),
    max_rack_count integer,
    floor_number integer,
    building_wing character varying,
    grid_coordinates character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: rooms_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rooms_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rooms_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rooms_id_seq OWNED BY public.rooms.id;


--
-- Name: salt_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salt_settings (
    id bigint NOT NULL,
    base_url character varying,
    username character varying,
    password character varying,
    ca_cert_path character varying,
    verify_ssl boolean DEFAULT true,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    bmc_sensor_polling_interval integer DEFAULT 5,
    bmc_collection_enabled boolean DEFAULT false,
    prometheus_pushgateway_url character varying,
    prometheus_url character varying
);


--
-- Name: salt_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.salt_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: salt_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.salt_settings_id_seq OWNED BY public.salt_settings.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: server_products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.server_products (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    product_series character varying(100),
    form_factor character varying(20),
    rack_height integer DEFAULT 1,
    qct_product_url character varying(500),
    cpu_generations character varying[] DEFAULT '{}'::character varying[],
    socket_count integer,
    max_tdp_watts integer,
    max_memory_gb integer,
    dimm_slots integer,
    memory_types character varying[] DEFAULT '{}'::character varying[],
    max_memory_speed_mhz integer,
    drive_bays jsonb DEFAULT '[]'::jsonb,
    pcie_slots jsonb DEFAULT '[]'::jsonb,
    power_supply_options jsonb DEFAULT '[]'::jsonb,
    gpu_support boolean DEFAULT false,
    network_options jsonb DEFAULT '[]'::jsonb,
    last_synced_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    image_url character varying
);


--
-- Name: server_products_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.server_products_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: server_products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.server_products_id_seq OWNED BY public.server_products.id;


--
-- Name: sites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sites (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: sites_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sites_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sites_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sites_id_seq OWNED BY public.sites.id;


--
-- Name: sync_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sync_logs (
    id bigint NOT NULL,
    source character varying(50) NOT NULL,
    products_added integer DEFAULT 0,
    products_updated integer DEFAULT 0,
    sync_errors jsonb DEFAULT '[]'::jsonb,
    completed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: sync_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sync_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sync_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sync_logs_id_seq OWNED BY public.sync_logs.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    email character varying DEFAULT ''::character varying NOT NULL,
    encrypted_password character varying DEFAULT ''::character varying NOT NULL,
    reset_password_token character varying,
    reset_password_sent_at timestamp(6) without time zone,
    remember_created_at timestamp(6) without time zone,
    name character varying,
    role integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: active_storage_attachments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments ALTER COLUMN id SET DEFAULT nextval('public.active_storage_attachments_id_seq'::regclass);


--
-- Name: active_storage_blobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs ALTER COLUMN id SET DEFAULT nextval('public.active_storage_blobs_id_seq'::regclass);


--
-- Name: active_storage_variant_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records ALTER COLUMN id SET DEFAULT nextval('public.active_storage_variant_records_id_seq'::regclass);


--
-- Name: api_keys id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_keys ALTER COLUMN id SET DEFAULT nextval('public.api_keys_id_seq'::regclass);


--
-- Name: artifact_indices id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.artifact_indices ALTER COLUMN id SET DEFAULT nextval('public.artifact_indices_id_seq'::regclass);


--
-- Name: benchmark_recipes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.benchmark_recipes ALTER COLUMN id SET DEFAULT nextval('public.benchmark_recipes_id_seq'::regclass);


--
-- Name: benchmark_runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.benchmark_runs ALTER COLUMN id SET DEFAULT nextval('public.benchmark_runs_id_seq'::regclass);


--
-- Name: bmc_credentials id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bmc_credentials ALTER COLUMN id SET DEFAULT nextval('public.bmc_credentials_id_seq'::regclass);


--
-- Name: bmc_inventories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bmc_inventories ALTER COLUMN id SET DEFAULT nextval('public.bmc_inventories_id_seq'::regclass);


--
-- Name: inventory_discrepancies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_discrepancies ALTER COLUMN id SET DEFAULT nextval('public.inventory_discrepancies_id_seq'::regclass);


--
-- Name: mlc_baselines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mlc_baselines ALTER COLUMN id SET DEFAULT nextval('public.mlc_baselines_id_seq'::regclass);


--
-- Name: mlc_installation_nodes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mlc_installation_nodes ALTER COLUMN id SET DEFAULT nextval('public.mlc_installation_nodes_id_seq'::regclass);


--
-- Name: mlc_installations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mlc_installations ALTER COLUMN id SET DEFAULT nextval('public.mlc_installations_id_seq'::regclass);


--
-- Name: node_states id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.node_states ALTER COLUMN id SET DEFAULT nextval('public.node_states_id_seq'::regclass);


--
-- Name: nodes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nodes ALTER COLUMN id SET DEFAULT nextval('public.nodes_id_seq'::regclass);


--
-- Name: notifications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications ALTER COLUMN id SET DEFAULT nextval('public.notifications_id_seq'::regclass);


--
-- Name: profiling_artifacts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiling_artifacts ALTER COLUMN id SET DEFAULT nextval('public.profiling_artifacts_id_seq'::regclass);


--
-- Name: profiling_recipes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiling_recipes ALTER COLUMN id SET DEFAULT nextval('public.profiling_recipes_id_seq'::regclass);


--
-- Name: profiling_runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiling_runs ALTER COLUMN id SET DEFAULT nextval('public.profiling_runs_id_seq'::regclass);


--
-- Name: racks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.racks ALTER COLUMN id SET DEFAULT nextval('public.racks_id_seq'::regclass);


--
-- Name: rooms id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rooms ALTER COLUMN id SET DEFAULT nextval('public.rooms_id_seq'::regclass);


--
-- Name: salt_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salt_settings ALTER COLUMN id SET DEFAULT nextval('public.salt_settings_id_seq'::regclass);


--
-- Name: server_products id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.server_products ALTER COLUMN id SET DEFAULT nextval('public.server_products_id_seq'::regclass);


--
-- Name: sites id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sites ALTER COLUMN id SET DEFAULT nextval('public.sites_id_seq'::regclass);


--
-- Name: sync_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sync_logs ALTER COLUMN id SET DEFAULT nextval('public.sync_logs_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: api_keys api_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT api_keys_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: artifact_indices artifact_indices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.artifact_indices
    ADD CONSTRAINT artifact_indices_pkey PRIMARY KEY (id);


--
-- Name: benchmark_recipes benchmark_recipes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.benchmark_recipes
    ADD CONSTRAINT benchmark_recipes_pkey PRIMARY KEY (id);


--
-- Name: benchmark_runs benchmark_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.benchmark_runs
    ADD CONSTRAINT benchmark_runs_pkey PRIMARY KEY (id);


--
-- Name: bmc_credentials bmc_credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bmc_credentials
    ADD CONSTRAINT bmc_credentials_pkey PRIMARY KEY (id);


--
-- Name: bmc_inventories bmc_inventories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bmc_inventories
    ADD CONSTRAINT bmc_inventories_pkey PRIMARY KEY (id);


--
-- Name: inventory_discrepancies inventory_discrepancies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_discrepancies
    ADD CONSTRAINT inventory_discrepancies_pkey PRIMARY KEY (id);


--
-- Name: mlc_baselines mlc_baselines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mlc_baselines
    ADD CONSTRAINT mlc_baselines_pkey PRIMARY KEY (id);


--
-- Name: mlc_installation_nodes mlc_installation_nodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mlc_installation_nodes
    ADD CONSTRAINT mlc_installation_nodes_pkey PRIMARY KEY (id);


--
-- Name: mlc_installations mlc_installations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mlc_installations
    ADD CONSTRAINT mlc_installations_pkey PRIMARY KEY (id);


--
-- Name: node_states node_states_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.node_states
    ADD CONSTRAINT node_states_pkey PRIMARY KEY (id);


--
-- Name: nodes nodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nodes
    ADD CONSTRAINT nodes_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: profiling_artifacts profiling_artifacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiling_artifacts
    ADD CONSTRAINT profiling_artifacts_pkey PRIMARY KEY (id);


--
-- Name: profiling_recipes profiling_recipes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiling_recipes
    ADD CONSTRAINT profiling_recipes_pkey PRIMARY KEY (id);


--
-- Name: profiling_runs profiling_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiling_runs
    ADD CONSTRAINT profiling_runs_pkey PRIMARY KEY (id);


--
-- Name: racks racks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.racks
    ADD CONSTRAINT racks_pkey PRIMARY KEY (id);


--
-- Name: rooms rooms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rooms
    ADD CONSTRAINT rooms_pkey PRIMARY KEY (id);


--
-- Name: salt_settings salt_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salt_settings
    ADD CONSTRAINT salt_settings_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: server_products server_products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.server_products
    ADD CONSTRAINT server_products_pkey PRIMARY KEY (id);


--
-- Name: sites sites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sites
    ADD CONSTRAINT sites_pkey PRIMARY KEY (id);


--
-- Name: sync_logs sync_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sync_logs
    ADD CONSTRAINT sync_logs_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: _materialized_hypertable_4_bucket_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _materialized_hypertable_4_bucket_idx ON _timescaledb_internal._materialized_hypertable_4 USING btree (bucket DESC);


--
-- Name: _materialized_hypertable_4_node_id_bucket_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _materialized_hypertable_4_node_id_bucket_idx ON _timescaledb_internal._materialized_hypertable_4 USING btree (node_id, bucket DESC);


--
-- Name: _materialized_hypertable_4_sensor_name_bucket_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _materialized_hypertable_4_sensor_name_bucket_idx ON _timescaledb_internal._materialized_hypertable_4 USING btree (sensor_name, bucket DESC);


--
-- Name: _materialized_hypertable_4_sensor_type_bucket_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _materialized_hypertable_4_sensor_type_bucket_idx ON _timescaledb_internal._materialized_hypertable_4 USING btree (sensor_type, bucket DESC);


--
-- Name: _materialized_hypertable_4_unit_bucket_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: -
--

CREATE INDEX _materialized_hypertable_4_unit_bucket_idx ON _timescaledb_internal._materialized_hypertable_4 USING btree (unit, bucket DESC);


--
-- Name: bmc_sensor_readings_recorded_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bmc_sensor_readings_recorded_at_idx ON public.bmc_sensor_readings USING btree (recorded_at DESC);


--
-- Name: idx_on_mlc_installation_id_node_id_79f3adb797; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_mlc_installation_id_node_id_79f3adb797 ON public.mlc_installation_nodes USING btree (mlc_installation_id, node_id);


--
-- Name: idx_sensor_readings_node_time_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sensor_readings_node_time_type ON public.bmc_sensor_readings USING btree (node_id, recorded_at, sensor_type);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_api_keys_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_api_keys_on_token ON public.api_keys USING btree (token);


--
-- Name: index_artifact_indices_on_benchmark_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_artifact_indices_on_benchmark_run_id ON public.artifact_indices USING btree (benchmark_run_id);


--
-- Name: index_benchmark_recipes_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_benchmark_recipes_on_name ON public.benchmark_recipes USING btree (name);


--
-- Name: index_benchmark_recipes_on_name_and_version; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_benchmark_recipes_on_name_and_version ON public.benchmark_recipes USING btree (name, version);


--
-- Name: index_benchmark_recipes_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_benchmark_recipes_on_slug ON public.benchmark_recipes USING btree (slug);


--
-- Name: index_benchmark_runs_on_benchmark_recipe_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_benchmark_runs_on_benchmark_recipe_id ON public.benchmark_runs USING btree (benchmark_recipe_id);


--
-- Name: index_benchmark_runs_on_node_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_benchmark_runs_on_node_id ON public.benchmark_runs USING btree (node_id);


--
-- Name: index_benchmark_runs_on_node_id_and_started_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_benchmark_runs_on_node_id_and_started_at ON public.benchmark_runs USING btree (node_id, started_at DESC);


--
-- Name: index_benchmark_runs_on_started_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_benchmark_runs_on_started_at ON public.benchmark_runs USING btree (started_at);


--
-- Name: index_benchmark_runs_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_benchmark_runs_on_status ON public.benchmark_runs USING btree (status);


--
-- Name: index_benchmark_runs_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_benchmark_runs_on_uuid ON public.benchmark_runs USING btree (uuid);


--
-- Name: index_bmc_credentials_on_is_global_default; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_bmc_credentials_on_is_global_default ON public.bmc_credentials USING btree (is_global_default) WHERE (is_global_default = true);


--
-- Name: index_bmc_credentials_on_node_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_bmc_credentials_on_node_id ON public.bmc_credentials USING btree (node_id) WHERE (node_id IS NOT NULL);


--
-- Name: index_bmc_inventories_on_captured_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bmc_inventories_on_captured_at ON public.bmc_inventories USING btree (captured_at);


--
-- Name: index_bmc_inventories_on_node_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bmc_inventories_on_node_id ON public.bmc_inventories USING btree (node_id);


--
-- Name: index_inventory_discrepancies_on_node_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inventory_discrepancies_on_node_id ON public.inventory_discrepancies USING btree (node_id);


--
-- Name: index_inventory_discrepancies_on_node_id_and_resolved_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inventory_discrepancies_on_node_id_and_resolved_at ON public.inventory_discrepancies USING btree (node_id, resolved_at);


--
-- Name: index_mlc_baselines_on_benchmark_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_mlc_baselines_on_benchmark_run_id ON public.mlc_baselines USING btree (benchmark_run_id);


--
-- Name: index_mlc_baselines_on_node_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_mlc_baselines_on_node_id ON public.mlc_baselines USING btree (node_id);


--
-- Name: index_mlc_baselines_on_node_id_and_metric_type; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_mlc_baselines_on_node_id_and_metric_type ON public.mlc_baselines USING btree (node_id, metric_type);


--
-- Name: index_mlc_installation_nodes_on_mlc_installation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_mlc_installation_nodes_on_mlc_installation_id ON public.mlc_installation_nodes USING btree (mlc_installation_id);


--
-- Name: index_mlc_installation_nodes_on_node_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_mlc_installation_nodes_on_node_id ON public.mlc_installation_nodes USING btree (node_id);


--
-- Name: index_mlc_installations_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_mlc_installations_on_created_by_id ON public.mlc_installations USING btree (created_by_id);


--
-- Name: index_mlc_installations_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_mlc_installations_on_uuid ON public.mlc_installations USING btree (uuid);


--
-- Name: index_node_states_on_captured_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_node_states_on_captured_at ON public.node_states USING btree (captured_at);


--
-- Name: index_node_states_on_node_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_node_states_on_node_id ON public.node_states USING btree (node_id);


--
-- Name: index_node_states_on_node_id_and_captured_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_node_states_on_node_id_and_captured_at ON public.node_states USING btree (node_id, captured_at DESC);


--
-- Name: index_nodes_on_api_key_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_nodes_on_api_key_id ON public.nodes USING btree (api_key_id);


--
-- Name: index_nodes_on_hostname; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_nodes_on_hostname ON public.nodes USING btree (hostname);


--
-- Name: index_nodes_on_rack_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_nodes_on_rack_id ON public.nodes USING btree (rack_id);


--
-- Name: index_nodes_on_rack_id_and_rack_face_and_rack_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_nodes_on_rack_id_and_rack_face_and_rack_position ON public.nodes USING btree (rack_id, rack_face, rack_position);


--
-- Name: index_nodes_on_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_nodes_on_role ON public.nodes USING btree (role);


--
-- Name: index_nodes_on_salt_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_nodes_on_salt_status ON public.nodes USING btree (salt_status);


--
-- Name: index_nodes_on_server_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_nodes_on_server_product_id ON public.nodes USING btree (server_product_id);


--
-- Name: index_nodes_on_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_nodes_on_source ON public.nodes USING btree (source);


--
-- Name: index_nodes_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_nodes_on_uuid ON public.nodes USING btree (uuid);


--
-- Name: index_notifications_on_resource_type_and_resource_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_resource_type_and_resource_id ON public.notifications USING btree (resource_type, resource_id);


--
-- Name: index_notifications_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_user_id ON public.notifications USING btree (user_id);


--
-- Name: index_notifications_on_user_id_and_archived_and_read; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_user_id_and_archived_and_read ON public.notifications USING btree (user_id, archived, read);


--
-- Name: index_notifications_on_user_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_user_id_and_created_at ON public.notifications USING btree (user_id, created_at);


--
-- Name: index_profiling_artifacts_on_profiling_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_profiling_artifacts_on_profiling_run_id ON public.profiling_artifacts USING btree (profiling_run_id);


--
-- Name: index_profiling_artifacts_on_profiling_run_id_and_filename; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_profiling_artifacts_on_profiling_run_id_and_filename ON public.profiling_artifacts USING btree (profiling_run_id, filename);


--
-- Name: index_profiling_recipes_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_profiling_recipes_on_slug ON public.profiling_recipes USING btree (slug);


--
-- Name: index_profiling_recipes_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_profiling_recipes_on_status ON public.profiling_recipes USING btree (status);


--
-- Name: index_profiling_recipes_on_tool; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_profiling_recipes_on_tool ON public.profiling_recipes USING btree (tool);


--
-- Name: index_profiling_runs_on_node_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_profiling_runs_on_node_id ON public.profiling_runs USING btree (node_id);


--
-- Name: index_profiling_runs_on_node_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_profiling_runs_on_node_id_and_created_at ON public.profiling_runs USING btree (node_id, created_at DESC);


--
-- Name: index_profiling_runs_on_profiling_recipe_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_profiling_runs_on_profiling_recipe_id ON public.profiling_runs USING btree (profiling_recipe_id);


--
-- Name: index_profiling_runs_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_profiling_runs_on_status ON public.profiling_runs USING btree (status);


--
-- Name: index_profiling_runs_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_profiling_runs_on_user_id ON public.profiling_runs USING btree (user_id);


--
-- Name: index_profiling_runs_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_profiling_runs_on_uuid ON public.profiling_runs USING btree (uuid);


--
-- Name: index_racks_on_room_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_racks_on_room_id ON public.racks USING btree (room_id);


--
-- Name: index_racks_on_room_id_and_facility_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_racks_on_room_id_and_facility_id ON public.racks USING btree (room_id, facility_id) WHERE (facility_id IS NOT NULL);


--
-- Name: index_racks_on_room_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_racks_on_room_id_and_name ON public.racks USING btree (room_id, name);


--
-- Name: index_racks_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_racks_on_status ON public.racks USING btree (status);


--
-- Name: index_rooms_on_site_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rooms_on_site_id ON public.rooms USING btree (site_id);


--
-- Name: index_rooms_on_site_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_rooms_on_site_id_and_name ON public.rooms USING btree (site_id, name);


--
-- Name: index_server_products_on_form_factor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_server_products_on_form_factor ON public.server_products USING btree (form_factor);


--
-- Name: index_server_products_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_server_products_on_name ON public.server_products USING btree (name);


--
-- Name: index_server_products_on_product_series; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_server_products_on_product_series ON public.server_products USING btree (product_series);


--
-- Name: index_sites_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sites_on_name ON public.sites USING btree (name);


--
-- Name: index_sync_logs_on_completed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sync_logs_on_completed_at ON public.sync_logs USING btree (completed_at);


--
-- Name: index_sync_logs_on_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sync_logs_on_source ON public.sync_logs USING btree (source);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_reset_password_token ON public.users USING btree (reset_password_token);


--
-- Name: mlc_installations fk_rails_003c1e5d57; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mlc_installations
    ADD CONSTRAINT fk_rails_003c1e5d57 FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: inventory_discrepancies fk_rails_138e1ec27e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_discrepancies
    ADD CONSTRAINT fk_rails_138e1ec27e FOREIGN KEY (node_id) REFERENCES public.nodes(id);


--
-- Name: racks fk_rails_2ea4aed728; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.racks
    ADD CONSTRAINT fk_rails_2ea4aed728 FOREIGN KEY (room_id) REFERENCES public.rooms(id);


--
-- Name: mlc_installation_nodes fk_rails_357ca2e6f9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mlc_installation_nodes
    ADD CONSTRAINT fk_rails_357ca2e6f9 FOREIGN KEY (mlc_installation_id) REFERENCES public.mlc_installations(id);


--
-- Name: bmc_sensor_readings fk_rails_39a2f45b2d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bmc_sensor_readings
    ADD CONSTRAINT fk_rails_39a2f45b2d FOREIGN KEY (node_id) REFERENCES public.nodes(id);


--
-- Name: profiling_artifacts fk_rails_3ae08bec38; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiling_artifacts
    ADD CONSTRAINT fk_rails_3ae08bec38 FOREIGN KEY (profiling_run_id) REFERENCES public.profiling_runs(id);


--
-- Name: profiling_runs fk_rails_3c539cb5b4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiling_runs
    ADD CONSTRAINT fk_rails_3c539cb5b4 FOREIGN KEY (profiling_recipe_id) REFERENCES public.profiling_recipes(id);


--
-- Name: bmc_inventories fk_rails_428e9f3eeb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bmc_inventories
    ADD CONSTRAINT fk_rails_428e9f3eeb FOREIGN KEY (node_id) REFERENCES public.nodes(id);


--
-- Name: nodes fk_rails_68223c9e89; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nodes
    ADD CONSTRAINT fk_rails_68223c9e89 FOREIGN KEY (server_product_id) REFERENCES public.server_products(id);


--
-- Name: artifact_indices fk_rails_699a8a24dd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.artifact_indices
    ADD CONSTRAINT fk_rails_699a8a24dd FOREIGN KEY (benchmark_run_id) REFERENCES public.benchmark_runs(id);


--
-- Name: bmc_credentials fk_rails_6c5309b8cd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bmc_credentials
    ADD CONSTRAINT fk_rails_6c5309b8cd FOREIGN KEY (node_id) REFERENCES public.nodes(id);


--
-- Name: mlc_baselines fk_rails_72855e6c51; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mlc_baselines
    ADD CONSTRAINT fk_rails_72855e6c51 FOREIGN KEY (benchmark_run_id) REFERENCES public.benchmark_runs(id);


--
-- Name: benchmark_runs fk_rails_819afe8684; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.benchmark_runs
    ADD CONSTRAINT fk_rails_819afe8684 FOREIGN KEY (benchmark_recipe_id) REFERENCES public.benchmark_recipes(id);


--
-- Name: mlc_baselines fk_rails_855e51b8dd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mlc_baselines
    ADD CONSTRAINT fk_rails_855e51b8dd FOREIGN KEY (node_id) REFERENCES public.nodes(id);


--
-- Name: rooms fk_rails_857be8f75c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rooms
    ADD CONSTRAINT fk_rails_857be8f75c FOREIGN KEY (site_id) REFERENCES public.sites(id);


--
-- Name: nodes fk_rails_9386283f4d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nodes
    ADD CONSTRAINT fk_rails_9386283f4d FOREIGN KEY (rack_id) REFERENCES public.racks(id);


--
-- Name: benchmark_runs fk_rails_958d396e45; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.benchmark_runs
    ADD CONSTRAINT fk_rails_958d396e45 FOREIGN KEY (node_id) REFERENCES public.nodes(id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: profiling_runs fk_rails_9b52076643; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiling_runs
    ADD CONSTRAINT fk_rails_9b52076643 FOREIGN KEY (node_id) REFERENCES public.nodes(id);


--
-- Name: node_states fk_rails_9c05902e57; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.node_states
    ADD CONSTRAINT fk_rails_9c05902e57 FOREIGN KEY (node_id) REFERENCES public.nodes(id);


--
-- Name: notifications fk_rails_b080fb4855; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT fk_rails_b080fb4855 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: nodes fk_rails_bf4814f99a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nodes
    ADD CONSTRAINT fk_rails_bf4814f99a FOREIGN KEY (api_key_id) REFERENCES public.api_keys(id);


--
-- Name: mlc_installation_nodes fk_rails_c2b02adc35; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mlc_installation_nodes
    ADD CONSTRAINT fk_rails_c2b02adc35 FOREIGN KEY (node_id) REFERENCES public.nodes(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: profiling_runs fk_rails_f0cf702ff4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiling_runs
    ADD CONSTRAINT fk_rails_f0cf702ff4 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260131000005'),
('20260131000004'),
('20260131000003'),
('20260131000002'),
('20260131000001'),
('20260130131002'),
('20260130004255'),
('20260129162820'),
('20260128021750'),
('20260128021721'),
('20260127052641'),
('20260127021056'),
('20260126234127'),
('20260123151557'),
('20260123100001'),
('20260123100000'),
('20260122052447'),
('20260122052408'),
('20260122052338'),
('20260122025925'),
('20260122025219'),
('20260122024144'),
('20260121160002'),
('20260121160001'),
('20260121160000'),
('20260121152752'),
('20260121070141'),
('20260121044253'),
('20260121044005'),
('20260121043945'),
('20260121013125'),
('20260120174743'),
('20260120174010'),
('20260120174009'),
('20260117172816'),
('20260117071841'),
('20260117031735'),
('20260116080006'),
('20260116065517'),
('20260116063243'),
('20260116024022'),
('20260116023704'),
('20260115144205'),
('20260115061734'),
('20260115061733'),
('20260115061717'),
('20260115033253'),
('20260114230138'),
('20260114064351'),
('20260114053410'),
('20260114053408'),
('20260114042002'),
('20260112032903'),
('20260109062941'),
('20260108030000'),
('20260108023644'),
('20260107023444'),
('20260107020301'),
('20260107015252'),
('20260107011724'),
('20260107002806'),
('20260105082609'),
('20260105075606'),
('20260105042101'),
('20260104235238'),
('20260102083925'),
('20260102083532'),
('20260102065307'),
('20251229011555'),
('20251229011547'),
('20251229005637'),
('20251229004254'),
('20251229001212');

