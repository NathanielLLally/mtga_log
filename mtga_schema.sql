--
-- PostgreSQL database dump
--

-- Dumped from database version 16.8
-- Dumped by pg_dump version 16.8

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

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: mtga_deck; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.mtga_deck (
    _id integer NOT NULL,
    id uuid NOT NULL,
    cardid integer NOT NULL,
    quantity integer NOT NULL,
    sha256_hex character varying(255)
);


ALTER TABLE public.mtga_deck OWNER TO postgres;

--
-- Name: mtga_deck__id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.mtga_deck ALTER COLUMN _id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.mtga_deck__id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: mtga_deck_attributes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.mtga_deck_attributes (
    _id integer NOT NULL,
    id uuid NOT NULL,
    player character varying(16) NOT NULL,
    last_played timestamp with time zone,
    last_updated timestamp with time zone,
    name character varying(255) NOT NULL,
    sha256_hex character varying(255) NOT NULL,
    format character varying(80) NOT NULL
);


ALTER TABLE public.mtga_deck_attributes OWNER TO postgres;

--
-- Name: mtga_deck_attributes__id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.mtga_deck_attributes ALTER COLUMN _id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.mtga_deck_attributes__id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: mtga_deck_summary; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.mtga_deck_summary (
    _id integer NOT NULL,
    cid uuid NOT NULL,
    ev_name character varying(80),
    id uuid NOT NULL,
    sha256_hex character varying(255),
    name character varying(255),
    last_updated timestamp with time zone,
    last_played timestamp with time zone,
    format character varying(80) NOT NULL,
    win integer,
    loss integer,
    player character varying(16) NOT NULL
);


ALTER TABLE public.mtga_deck_summary OWNER TO postgres;

--
-- Name: mtga_deck_summary__id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.mtga_deck_summary ALTER COLUMN _id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.mtga_deck_summary__id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: vw_mtga_deck_stats; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_mtga_deck_stats AS
 WITH totals AS (
         SELECT mtga_deck_summary.player,
            sum((mtga_deck_summary.win + mtga_deck_summary.loss)) AS total,
            sum(mtga_deck_summary.win) AS total_wins,
            sum(mtga_deck_summary.loss) AS total_losses,
            mtga_deck_summary.ev_name,
            mtga_deck_summary.name
           FROM public.mtga_deck_summary
          GROUP BY mtga_deck_summary.player, mtga_deck_summary.name, mtga_deck_summary.ev_name
        )
 SELECT player,
    ev_name,
    played,
    total_wins,
    total_losses,
    twin_ratio,
    name,
    wins,
    losses,
    win_ratio,
    modified
   FROM ( SELECT sq.player,
            sq.ev_name,
            totals.total AS played,
            totals.total_wins,
            totals.total_losses,
            (((totals.total_wins)::double precision / (totals.total)::double precision))::numeric(5,2) AS twin_ratio,
            sq.name,
            sum(sq.win) AS wins,
            sum(sq.loss) AS losses,
            (((sum(sq.win))::double precision / (sum((sq.win + sq.loss)))::double precision))::numeric(5,2) AS win_ratio,
            max(sq.last_updated) AS modified
           FROM (( SELECT mtga_deck_summary.player,
                    mtga_deck_summary.sha256_hex,
                    mtga_deck_summary.last_updated,
                    mtga_deck_summary.name,
                    mtga_deck_summary.ev_name,
                    mtga_deck_summary.win,
                    mtga_deck_summary.loss
                   FROM public.mtga_deck_summary
                  ORDER BY mtga_deck_summary.name) sq
             JOIN totals ON ((((sq.player)::text = (totals.player)::text) AND ((sq.name)::text = (totals.name)::text) AND ((sq.ev_name)::text = (totals.ev_name)::text))))
          WHERE (totals.total > 0)
          GROUP BY sq.player, sq.name, sq.ev_name, totals.total, totals.total_wins, totals.total_losses, sq.sha256_hex
          ORDER BY sq.player, sq.name) unnamed_subquery
  WHERE (modified IS NOT NULL);


ALTER VIEW public.vw_mtga_deck_stats OWNER TO postgres;

--
-- Name: mtga_deck_attributes mtga_deck_attributes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mtga_deck_attributes
    ADD CONSTRAINT mtga_deck_attributes_pkey PRIMARY KEY (_id);


--
-- Name: mtga_deck mtga_deck_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mtga_deck
    ADD CONSTRAINT mtga_deck_pkey PRIMARY KEY (_id);


--
-- Name: mtga_deck_summary mtga_deck_summary_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mtga_deck_summary
    ADD CONSTRAINT mtga_deck_summary_pkey PRIMARY KEY (_id);


--
-- Name: mtga_deck_summary mtga_deck_summary_player_cid_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mtga_deck_summary
    ADD CONSTRAINT mtga_deck_summary_player_cid_id_key UNIQUE (player, cid, id);


--
-- Name: mtga_deck_u; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX mtga_deck_u ON public.mtga_deck USING btree (id, sha256_hex, cardid);


--
-- Name: mtgads_u; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX mtgads_u ON public.mtga_deck_attributes USING btree (id, sha256_hex);


--
-- PostgreSQL database dump complete
--

