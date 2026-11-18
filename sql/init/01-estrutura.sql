--
-- PostgreSQL database dump
--


-- Dumped from database version 16.15 (Debian 16.15-1.pgdg13+2)
-- Dumped by pg_dump version 16.15 (Debian 16.15-1.pgdg13+2)

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
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--



--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--



--
-- Name: agenda_cancelar(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_cancelar(p_chat_id text) RETURNS TABLE(ok boolean, mensagem text, quando text)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_id     bigint;
  v_inicio timestamptz;
BEGIN
  SELECT a.id, a.inicio INTO v_id, v_inicio FROM agendamentos_treinamento a
   WHERE a.chat_id = p_chat_id AND a.status = 'confirmado' AND a.inicio > now()
   ORDER BY a.inicio LIMIT 1;
  IF v_id IS NULL THEN
    RETURN QUERY SELECT false, 'SEM_AGENDAMENTO: nao ha treinamento futuro para cancelar', NULL::text; RETURN;
  END IF;
  UPDATE agendamentos_treinamento SET status = 'cancelado', atualizado_em = now() WHERE id = v_id;
  RETURN QUERY SELECT true, 'CANCELADO', agenda_rotulo(v_inicio);
END;
$$;


--
-- Name: agenda_consultar(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_consultar(p_chat_id text) RETURNS TABLE(situacao text, quando text)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
  RETURN QUERY
    SELECT 'CONFIRMADO'::text, agenda_rotulo(a.inicio)
      FROM agendamentos_treinamento a
     WHERE a.chat_id = p_chat_id AND a.status = 'confirmado' AND a.inicio > now()
     ORDER BY a.inicio;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'SEM_AGENDAMENTO'::text, NULL::text;
  END IF;
END;
$$;


--
-- Name: agenda_lembretes_pendentes(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_lembretes_pendentes() RETURNS TABLE(chat_id text, idioma text, texto text)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_tz text := 'America/Sao_Paulo';
BEGIN
  RETURN QUERY
  WITH alvo AS (
    UPDATE agendamentos_treinamento a
       SET lembrete_em = now()
     WHERE a.status = 'confirmado'
       AND a.lembrete_em IS NULL
       AND a.inicio > now()
       AND a.inicio <= now() + interval '70 minutes'
    RETURNING a.chat_id AS cid, a.inicio AS ini
  )
  SELECT al.cid,
         coalesce(nullif(ci.idioma,''), 'pt'),
         CASE WHEN coalesce(nullif(ci.idioma,''), 'pt') = 'es'
           THEN 'Hola! Tu entrenamiento es hoy a las '
                || to_char(al.ini AT TIME ZONE v_tz, 'HH24:MI')
                || ', en poco mas de una hora. Si necesitas reprogramar o cancelar, solo dime por aqui.'
           ELSE 'Oi! Seu treinamento e hoje as '
                || to_char(al.ini AT TIME ZONE v_tz, 'HH24:MI')
                || ', daqui a pouco mais de uma hora. Se precisar remarcar ou cancelar, e so me falar por aqui.'
         END
    FROM alvo al
    LEFT JOIN cliente_idioma ci ON ci.chat_id = al.cid;
END;
$$;


--
-- Name: agenda_marcar(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_marcar(p_chat_id text, p_inicio text, p_nome text DEFAULT NULL::text) RETURNS TABLE(ok boolean, mensagem text, quando text)
    LANGUAGE plpgsql
    AS $$
DECLARE
  c        agenda_config;
  v_local  timestamp;
  v_inicio timestamptz;
  v_id     bigint;
BEGIN
  SELECT * INTO c FROM agenda_config WHERE id = 1;

  IF p_chat_id IS NULL OR p_chat_id = '' THEN
    RETURN QUERY SELECT false, 'SEM_CLIENTE: conversa nao identificada', NULL::text; RETURN;
  END IF;
  IF p_inicio IS NULL OR p_inicio !~ '^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}' THEN
    RETURN QUERY SELECT false, 'DATA_INVALIDA: envie no formato YYYY-MM-DD HH:MM', NULL::text; RETURN;
  END IF;

  v_local  := p_inicio::timestamp;
  v_inicio := v_local AT TIME ZONE c.fuso;

  IF EXTRACT(minute FROM v_local) <> 0 THEN
    RETURN QUERY SELECT false, 'HORARIO_INVALIDO: os treinamentos comecam sempre na hora cheia', NULL::text; RETURN;
  END IF;
  IF EXTRACT(isodow FROM v_local) > 5 THEN
    RETURN QUERY SELECT false, 'FORA_DOS_DIAS: treinamentos apenas de segunda a sexta', NULL::text; RETURN;
  END IF;
  IF EXTRACT(hour FROM v_local) < c.hora_inicio
     OR EXTRACT(hour FROM v_local) > c.hora_fim - (c.duracao_min / 60) THEN
    RETURN QUERY SELECT false,
      format('FORA_DO_HORARIO: atendemos das %s:00 as %s:00 (horario de Brasilia)', c.hora_inicio, c.hora_fim),
      NULL::text; RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM agenda_bloqueios b WHERE b.dia = v_local::date) THEN
    RETURN QUERY SELECT false, 'DIA_BLOQUEADO: nao ha treinamento nesse dia', NULL::text; RETURN;
  END IF;
  IF v_inicio < now() + make_interval(mins => c.antecedencia_min) THEN
    RETURN QUERY SELECT false,
      format('ANTECEDENCIA: e preciso pelo menos %s minutos de antecedencia', c.antecedencia_min),
      NULL::text; RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM agendamentos_treinamento a
              WHERE a.status = 'confirmado' AND a.inicio = v_inicio
                AND a.chat_id <> p_chat_id) THEN
    RETURN QUERY SELECT false, 'OCUPADO: esse horario ja esta reservado', NULL::text; RETURN;
  END IF;

  SELECT a.id INTO v_id FROM agendamentos_treinamento a
   WHERE a.chat_id = p_chat_id AND a.status = 'confirmado' AND a.inicio > now()
   ORDER BY a.inicio LIMIT 1;

  BEGIN
    IF v_id IS NOT NULL THEN
      UPDATE agendamentos_treinamento
         SET inicio = v_inicio,
             fim = v_inicio + make_interval(mins => c.duracao_min),
             nome_cliente = COALESCE(NULLIF(p_nome, ''), nome_cliente),
             atualizado_em = now()
       WHERE id = v_id;
      RETURN QUERY SELECT true, 'REAGENDADO', agenda_rotulo(v_inicio); RETURN;
    END IF;

    INSERT INTO agendamentos_treinamento (chat_id, nome_cliente, inicio, fim)
    VALUES (p_chat_id, NULLIF(p_nome, ''), v_inicio, v_inicio + make_interval(mins => c.duracao_min));
    RETURN QUERY SELECT true, 'AGENDADO', agenda_rotulo(v_inicio); RETURN;
  EXCEPTION WHEN unique_violation THEN
    RETURN QUERY SELECT false, 'OCUPADO: esse horario acabou de ser reservado', NULL::text; RETURN;
  END;
END;
$$;


--
-- Name: agenda_rotulo(timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_rotulo(p timestamp with time zone) RETURNS text
    LANGUAGE sql STABLE
    AS $$
  SELECT to_char(p AT TIME ZONE c.fuso, 'DD/MM') || ' (' ||
         CASE EXTRACT(isodow FROM p AT TIME ZONE c.fuso)
           WHEN 1 THEN 'seg' WHEN 2 THEN 'ter' WHEN 3 THEN 'qua'
           WHEN 4 THEN 'qui' WHEN 5 THEN 'sex' WHEN 6 THEN 'sab' ELSE 'dom' END ||
         ') as ' || to_char(p AT TIME ZONE c.fuso, 'HH24:MI')
    FROM agenda_config c WHERE c.id = 1;
$$;


--
-- Name: agenda_slots_livres(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_slots_livres(p_dia text DEFAULT NULL::text, p_limite integer DEFAULT 12) RETURNS TABLE(horario text, codigo text)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
  c agenda_config;
  v_dia date := NULL;
BEGIN
  SELECT * INTO c FROM agenda_config WHERE id = 1;
  IF p_dia IS NOT NULL AND p_dia ~ '^\d{4}-\d{2}-\d{2}$' THEN
    v_dia := p_dia::date;
  END IF;

  RETURN QUERY
  WITH dias AS (
    SELECT d::date AS dia
      FROM generate_series((now() AT TIME ZONE c.fuso)::date,
                           (now() AT TIME ZONE c.fuso)::date + c.horizonte_dias,
                           interval '1 day') AS d
  ),
  slots AS (
    SELECT ((dias.dia + make_interval(hours => h))::timestamp AT TIME ZONE c.fuso) AS inicio
      FROM dias
      CROSS JOIN generate_series(c.hora_inicio, c.hora_fim - (c.duracao_min / 60), 1) AS h
     WHERE EXTRACT(isodow FROM dias.dia) BETWEEN 1 AND 5
       AND (v_dia IS NULL OR dias.dia = v_dia)
       AND NOT EXISTS (SELECT 1 FROM agenda_bloqueios b WHERE b.dia = dias.dia)
  )
  SELECT agenda_rotulo(s.inicio),
         to_char(s.inicio AT TIME ZONE c.fuso, 'YYYY-MM-DD HH24:MI')
    FROM slots s
   WHERE s.inicio > now() + make_interval(mins => c.antecedencia_min)
     AND NOT EXISTS (SELECT 1 FROM agendamentos_treinamento a
                      WHERE a.status = 'confirmado' AND a.inicio = s.inicio)
   ORDER BY s.inicio
   LIMIT p_limite;
END;
$_$;


--
-- Name: crm_api(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.crm_api(p_acao text, p_payload jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_user text; v_chat text; v_est text; v_r jsonb; v_n int;
BEGIN
  IF p_acao = 'status' THEN
    SELECT count(*) INTO v_n FROM crm_usuarios;
    RETURN jsonb_build_object('ok', true, 'precisa_setup', v_n = 0);
  END IF;

  IF p_acao = 'primeiro_acesso' THEN
    SELECT count(*) INTO v_n FROM crm_usuarios;
    IF v_n > 0 THEN RETURN jsonb_build_object('ok', false, 'erro', 'JA_CONFIGURADO'); END IF;
    v_r := crm_usuario_criar(p_payload->>'usuario', p_payload->>'senha', p_payload->>'nome');
    IF (v_r->>'ok')::boolean IS NOT TRUE THEN RETURN v_r; END IF;
    RETURN crm_login(p_payload->>'usuario', p_payload->>'senha');
  END IF;

  IF p_acao = 'login' THEN
    RETURN crm_login(p_payload->>'usuario', p_payload->>'senha');
  END IF;

  v_user := crm_sessao_usuario(p_payload->>'token');
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'SESSAO_INVALIDA');
  END IF;
  v_chat := nullif(p_payload->>'chat_id','');

  IF p_acao = 'logout' THEN
    DELETE FROM crm_sessoes WHERE token = p_payload->>'token';
    RETURN jsonb_build_object('ok', true);

  ELSIF p_acao = 'dashboard' THEN
    RETURN crm_dashboard(coalesce((p_payload->>'dias')::int, 14));

  ELSIF p_acao = 'relatorio' THEN
    RETURN crm_relatorio(coalesce(p_payload->>'tipo','conversas'),
                         coalesce((p_payload->>'dias')::int, 30));

  ELSIF p_acao = 'equipe' THEN
    RETURN jsonb_build_object('ok', true,
      'usuarios', (SELECT coalesce(jsonb_agg(jsonb_build_object(
          'usuario', u.usuario, 'nome', coalesce(u.nome, u.usuario), 'ativo', u.ativo,
          'ultimo_acesso', to_char(u.ultimo_acesso AT TIME ZONE 'America/Sao_Paulo','DD/MM/YYYY HH24:MI')
        ) ORDER BY u.usuario), '[]'::jsonb) FROM crm_usuarios u));

  ELSIF p_acao = 'listar' THEN
    PERFORM crm_reconciliar(NULL);   -- coluna sempre fiel ao estado real
    RETURN jsonb_build_object(
      'ok', true, 'usuario', v_user,
      'agora', to_char(now() AT TIME ZONE 'America/Sao_Paulo','DD/MM/YYYY HH24:MI'),
      'estagios', (SELECT coalesce(jsonb_agg(to_jsonb(e) ORDER BY e.ordem), '[]'::jsonb) FROM crm_estagios e),
      'cards', (SELECT coalesce(jsonb_agg(x ORDER BY ord DESC), '[]'::jsonb) FROM (
         SELECT c.ultimo_contato AS ord,
                jsonb_build_object(
                  'chat_id', c.chat_id, 'telefone', c.telefone, 'nome', c.nome,
                  'nome_whatsapp', c.nome_whatsapp, 'lid', c.lid,
                  'estagio', c.estagio, 'idioma', c.idioma, 'responsavel', c.responsavel,
                  'notas', c.notas, 'ultima_mensagem', c.ultima_mensagem,
                  'ultima_direcao', c.ultima_direcao,
                  'total_entrada', c.total_entrada, 'total_saida', c.total_saida,
                  'minutos', floor(extract(epoch from now() - c.ultimo_contato)/60)::int,
                  'pausado', pausa_ativa(c.chat_id),
                  'treinamento', (SELECT agenda_rotulo(a.inicio) FROM agendamentos_treinamento a
                                   WHERE a.chat_id = c.chat_id AND a.status='confirmado' AND a.inicio > now()
                                   ORDER BY a.inicio LIMIT 1)
                ) AS x
           FROM crm_atendimentos c) s),
      'agenda', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                     'chat_id', a.chat_id, 'telefone', crm_contato_rotulo(a.chat_id),
                     'quando', agenda_rotulo(a.inicio)) ORDER BY a.inicio), '[]'::jsonb)
                   FROM agendamentos_treinamento a
                  WHERE a.status='confirmado' AND a.inicio > now())
    );

  ELSIF p_acao = 'conversa' THEN
    IF v_chat IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro','SEM_CHAT'); END IF;
    RETURN jsonb_build_object('ok', true, 'chat_id', v_chat,
      'mensagens', (SELECT coalesce(jsonb_agg(jsonb_build_object(
            'direcao', m.direcao, 'origem', m.origem, 'texto', m.texto, 'audio', m.eh_audio,
            'quando', to_char(m.criado_em AT TIME ZONE 'America/Sao_Paulo','DD/MM HH24:MI')
          ) ORDER BY m.id), '[]'::jsonb)
        FROM (SELECT * FROM crm_mensagens WHERE chat_id = v_chat ORDER BY id DESC LIMIT 60) m));

  ELSIF p_acao = 'mover' THEN
    v_est := p_payload->>'estagio';
    IF NOT EXISTS (SELECT 1 FROM crm_estagios WHERE estagio = v_est) THEN
      RETURN jsonb_build_object('ok', false, 'erro','ESTAGIO_INVALIDO');
    END IF;
    UPDATE crm_atendimentos SET estagio = v_est, movido_em = now(), atualizado_em = now() WHERE chat_id = v_chat;
    RETURN jsonb_build_object('ok', true, 'estagio', v_est);

  ELSIF p_acao = 'nota' THEN
    UPDATE crm_atendimentos SET notas = p_payload->>'notas', atualizado_em = now() WHERE chat_id = v_chat;
    RETURN jsonb_build_object('ok', true);

  ELSIF p_acao = 'assumir' THEN
    INSERT INTO pausa_humana (chat_id, motivo) VALUES (v_chat, 'Atendente assumiu pelo painel')
      ON CONFLICT (chat_id) DO UPDATE SET pausado_em = now(), motivo = EXCLUDED.motivo;
    UPDATE crm_atendimentos SET responsavel = v_user, estagio = 'em_atendimento', atualizado_em = now()
     WHERE chat_id = v_chat;
    RETURN jsonb_build_object('ok', true,
      'aviso', 'Bot pausado por ' || pausa_minutos() || ' minutos neste chat');

  ELSIF p_acao = 'devolver' THEN
    DELETE FROM pausa_humana WHERE chat_id = v_chat;
    UPDATE crm_atendimentos SET estagio='bot_atendendo', responsavel=NULL, atualizado_em=now()
     WHERE chat_id = v_chat;
    RETURN jsonb_build_object('ok', true, 'aviso', 'Bot reativado neste chat');

  ELSIF p_acao = 'resolver' THEN
    DELETE FROM pausa_humana WHERE chat_id = v_chat;
    UPDATE crm_atendimentos SET estagio='resolvido', atualizado_em=now() WHERE chat_id = v_chat;
    RETURN jsonb_build_object('ok', true);

  ELSIF p_acao = 'criar_usuario' THEN
    RETURN crm_usuario_criar(p_payload->>'usuario', p_payload->>'senha', p_payload->>'nome');

  ELSIF p_acao = 'trocar_senha' THEN
    RETURN crm_senha_trocar(v_user, p_payload->>'atual', p_payload->>'nova');

  END IF;
  RETURN jsonb_build_object('ok', false, 'erro','ACAO_DESCONHECIDA');
END;
$$;


--
-- Name: crm_contato_rotulo(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.crm_contato_rotulo(p_chat_id text) RETURNS text
    LANGUAGE sql STABLE
    AS $$
  SELECT CASE
    WHEN c.chat_id IS NULL THEN split_part(x.k,'@',1)
    WHEN coalesce(nullif(c.nome,''), nullif(c.nome_whatsapp,'')) IS NOT NULL AND c.telefone IS NOT NULL
      THEN coalesce(nullif(c.nome,''), c.nome_whatsapp) || ' · +' || c.telefone
    WHEN c.telefone IS NOT NULL THEN '+' || c.telefone
    WHEN coalesce(nullif(c.nome,''), nullif(c.nome_whatsapp,'')) IS NOT NULL
      THEN coalesce(nullif(c.nome,''), c.nome_whatsapp) || ' · ' || coalesce(c.lid, split_part(c.chat_id,'@',1))
    ELSE coalesce(c.lid, split_part(c.chat_id,'@',1)) || ' (ID do WhatsApp)'
  END
  FROM (SELECT p_chat_id AS k) x
  LEFT JOIN crm_atendimentos c ON c.chat_id = x.k;
$$;


--
-- Name: crm_dashboard(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.crm_dashboard(p_dias integer DEFAULT 14) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
  v_tz   text := 'America/Sao_Paulo';
  v_dias int  := greatest(1, least(coalesce(p_dias,14), 90));
  v_ini  timestamptz := now() - make_interval(days => v_dias);
BEGIN
  RETURN jsonb_build_object(
    'ok', true,
    'dias', v_dias,
    'gerado_em', to_char(now() AT TIME ZONE v_tz, 'DD/MM/YYYY HH24:MI'),

    -- ---------- numeros de topo ----------
    'kpis', jsonb_build_object(
      'conversas',      (SELECT count(*) FROM crm_atendimentos WHERE ultimo_contato   >= v_ini),
      'novas',          (SELECT count(*) FROM crm_atendimentos WHERE primeiro_contato >= v_ini),
      'recebidas',      (SELECT count(*) FROM crm_mensagens WHERE direcao='entrada' AND criado_em >= v_ini),
      'enviadas',       (SELECT count(*) FROM crm_mensagens WHERE direcao='saida'   AND criado_em >= v_ini),
      'com_humano',     (SELECT count(DISTINCT chat_id) FROM crm_mensagens
                          WHERE origem='humano' AND criado_em >= v_ini),
      'fila_agora',     (SELECT count(*) FROM crm_atendimentos WHERE estagio='aguardando_humano'),
      'pausados_agora', (SELECT count(*) FROM pausa_humana p WHERE pausa_ativa(p.chat_id)),
      'marcados',       (SELECT count(*) FROM agendamentos_treinamento WHERE criado_em >= v_ini),
      'futuros',        (SELECT count(*) FROM agendamentos_treinamento
                          WHERE status='confirmado' AND inicio > now()),
      'cancelados',     (SELECT count(*) FROM agendamentos_treinamento
                          WHERE status='cancelado' AND atualizado_em >= v_ini),
      -- % de conversas que o bot levou sozinho, sem humano entrar
      'autonomia', (SELECT CASE WHEN count(*) = 0 THEN NULL ELSE
                      round(100.0 * count(*) FILTER (
                        WHERE NOT EXISTS (SELECT 1 FROM crm_mensagens m
                                           WHERE m.chat_id = c.chat_id AND m.origem='humano')) / count(*))
                    END FROM crm_atendimentos c WHERE c.ultimo_contato >= v_ini),
      -- segundos medios entre a mensagem do cliente e a resposta do bot
      'resposta_seg', (
        WITH pares AS (
          SELECT m.criado_em AS entrada,
                 (SELECT min(s.criado_em) FROM crm_mensagens s
                   WHERE s.chat_id = m.chat_id AND s.direcao='saida' AND s.origem='bot'
                     AND s.criado_em > m.criado_em) AS saida
            FROM crm_mensagens m
           WHERE m.direcao='entrada' AND m.criado_em >= v_ini)
        SELECT round(avg(extract(epoch FROM saida - entrada)))
          FROM pares WHERE saida IS NOT NULL AND saida - entrada < interval '10 minutes')
    ),

    -- ---------- volume por dia ----------
    'por_dia', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                    'rotulo', to_char(d, 'DD/MM'),
                    'qtd', (SELECT count(*) FROM crm_mensagens m
                             WHERE m.direcao='entrada'
                               AND (m.criado_em AT TIME ZONE v_tz)::date = d)) ORDER BY d), '[]'::jsonb)
                  FROM generate_series((now() AT TIME ZONE v_tz)::date - (v_dias - 1),
                                       (now() AT TIME ZONE v_tz)::date, interval '1 day') d),

    -- ---------- volume por hora do dia (dimensionar equipe) ----------
    'por_hora', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                    'rotulo', lpad(h::text, 2, '0') || 'h',
                    'qtd', (SELECT count(*) FROM crm_mensagens m
                             WHERE m.direcao='entrada' AND m.criado_em >= v_ini
                               AND extract(hour FROM m.criado_em AT TIME ZONE v_tz) = h)) ORDER BY h), '[]'::jsonb)
                  FROM generate_series(0, 23) h),

    -- ---------- assuntos mais pedidos ----------
    'temas', (SELECT coalesce(jsonb_agg(jsonb_build_object('rotulo', t.tema, 'qtd', t.qtd)
                       ORDER BY t.qtd DESC), '[]'::jsonb)
                FROM (SELECT regexp_replace(audio, '-(pt|es)$', '') AS tema, count(*) AS qtd
                        FROM audios_enviados WHERE enviado_em >= v_ini GROUP BY 1) t),

    -- ---------- distribuicao atual do funil ----------
    'estagios', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                    'rotulo', e.titulo, 'cor', e.cor,
                    'qtd', (SELECT count(*) FROM crm_atendimentos c WHERE c.estagio = e.estagio))
                    ORDER BY e.ordem), '[]'::jsonb) FROM crm_estagios e),

    -- ---------- idioma dos clientes ----------
    'idiomas', (SELECT coalesce(jsonb_agg(jsonb_build_object('rotulo', i.idioma, 'qtd', i.qtd)
                        ORDER BY i.qtd DESC), '[]'::jsonb)
                 FROM (SELECT coalesce(nullif(idioma,''), 'nao definido') AS idioma, count(*) AS qtd
                         FROM crm_atendimentos GROUP BY 1) i)
  );
END;
$_$;


--
-- Name: crm_estagio_calculado(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.crm_estagio_calculado(p_chat text) RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  c crm_atendimentos%ROWTYPE;
  v_pausa pausa_humana%ROWTYPE;
  v_marcado_em timestamptz;
  v_quieto constant interval := interval '30 minutes';
BEGIN
  SELECT * INTO c FROM crm_atendimentos WHERE chat_id = p_chat;
  IF NOT FOUND THEN RETURN NULL; END IF;

  IF c.estagio = 'resolvido' THEN RETURN 'resolvido'; END IF;
  IF c.estagio = 'novo' AND c.ultima_direcao = 'entrada' THEN RETURN 'novo'; END IF;

  -- pausa do bot valendo: humano no comando
  IF pausa_ativa(p_chat) THEN
    SELECT * INTO v_pausa FROM pausa_humana
     WHERE chat_id = p_chat ORDER BY pausado_em DESC LIMIT 1;
    IF v_pausa.motivo ILIKE 'Cliente pediu%' AND NOT EXISTS (
         SELECT 1 FROM crm_mensagens m
          WHERE m.chat_id = p_chat AND m.origem = 'humano' AND m.criado_em >= v_pausa.pausado_em) THEN
      RETURN 'aguardando_humano';
    END IF;
    RETURN 'em_atendimento';
  END IF;

  -- treinamento futuro confirmado
  SELECT max(a.criado_em) INTO v_marcado_em
    FROM agendamentos_treinamento a
   WHERE a.chat_id = p_chat AND a.status = 'confirmado' AND a.inicio > now();

  IF v_marcado_em IS NOT NULL THEN
    -- cliente voltou a falar depois de agendar e a conversa ainda esta viva
    IF EXISTS (SELECT 1 FROM crm_mensagens m
                WHERE m.chat_id = p_chat AND m.direcao = 'entrada'
                  AND m.criado_em > v_marcado_em
                  AND m.criado_em > now() - v_quieto) THEN
      RETURN 'bot_atendendo';
    END IF;
    RETURN 'treinamento_agendado';
  END IF;

  RETURN 'bot_atendendo';
END; $$;


--
-- Name: crm_login(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.crm_login(p_usuario text, p_senha text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE v_u crm_usuarios; v_token text;
BEGIN
  SELECT * INTO v_u FROM crm_usuarios WHERE usuario = lower(trim(coalesce(p_usuario,'')));
  IF v_u.usuario IS NULL OR NOT v_u.ativo
     OR v_u.senha_hash <> crypt(coalesce(p_senha,''), v_u.senha_hash) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'CREDENCIAL_INVALIDA');
  END IF;
  DELETE FROM crm_sessoes WHERE expira_em < now();
  v_token := encode(gen_random_bytes(24), 'hex');
  INSERT INTO crm_sessoes (token, usuario) VALUES (v_token, v_u.usuario);
  UPDATE crm_usuarios SET ultimo_acesso = now() WHERE usuario = v_u.usuario;
  RETURN jsonb_build_object('ok', true, 'token', v_token,
                            'usuario', v_u.usuario, 'nome', coalesce(v_u.nome, v_u.usuario));
END; $$;


--
-- Name: crm_reconciliar(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.crm_reconciliar(p_chat text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE v_n integer;
BEGIN
  UPDATE crm_atendimentos c
     SET estagio = x.calc, atualizado_em = now()
    FROM (SELECT chat_id, crm_estagio_calculado(chat_id) AS calc
            FROM crm_atendimentos
           WHERE (p_chat IS NULL OR chat_id = p_chat)) x
   WHERE c.chat_id = x.chat_id
     AND x.calc IS NOT NULL
     AND c.estagio IS DISTINCT FROM x.calc
     AND NOT (c.movido_em IS NOT NULL AND c.movido_em >= c.ultimo_contato);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END; $$;


--
-- Name: crm_registrar(text, text, boolean, text, text, boolean, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.crm_registrar(p_chat_id text, p_to_id text, p_from_me boolean, p_source text, p_texto text, p_eh_audio boolean DEFAULT false, p_telefone text DEFAULT NULL::text, p_nome text DEFAULT NULL::text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_alvo text; v_direcao text; v_origem text; v_estagio text; v_atual text;
  v_tel text; v_lid text; v_nome text;
BEGIN
  v_alvo := CASE WHEN p_from_me
                 THEN coalesce(NULLIF(p_to_id,''), NULLIF(p_chat_id,''))
                 ELSE NULLIF(p_chat_id,'') END;
  IF v_alvo IS NULL THEN RETURN 'IGNORADO'; END IF;
  IF v_alvo LIKE '@%' THEN RETURN 'IGNORADO'; END IF;            -- sem numero
  IF v_alvo LIKE '%@g.us' OR v_alvo LIKE 'status@%' OR v_alvo LIKE '%@newsletter' THEN RETURN 'IGNORADO'; END IF;

  -- telefone: so numero real. LID vai para a coluna propria.
  v_tel := regexp_replace(coalesce(p_telefone,''), '\D', '', 'g');
  IF length(v_tel) NOT BETWEEN 8 AND 15 THEN v_tel := NULL; END IF;
  IF v_tel IS NULL AND (v_alvo LIKE '%@c.us' OR v_alvo LIKE '%@s.whatsapp.net') THEN
    v_tel := split_part(v_alvo,'@',1);
  END IF;
  v_lid := CASE WHEN v_alvo LIKE '%@lid' THEN split_part(v_alvo,'@',1) END;
  -- pushName de mensagem nossa e o NOSSO nome: so vale o do cliente
  v_nome := CASE WHEN p_from_me THEN NULL ELSE NULLIF(left(trim(coalesce(p_nome,'')),80),'') END;

  IF p_from_me THEN
    v_direcao := 'saida';
    v_origem  := CASE WHEN p_source = 'app' THEN 'humano' ELSE 'bot' END;
  ELSE
    v_direcao := 'entrada';
    v_origem  := 'cliente';
  END IF;

  SELECT c.estagio INTO v_atual FROM crm_atendimentos c WHERE c.chat_id = v_alvo;

  IF v_origem = 'humano' THEN                              v_estagio := 'em_atendimento';
  ELSIF v_atual IS NULL THEN                               v_estagio := 'novo';
  ELSIF v_atual = 'resolvido' AND v_direcao='entrada' THEN v_estagio := 'novo';
  ELSIF v_atual = 'novo' AND v_origem = 'bot' THEN         v_estagio := 'bot_atendendo';
  ELSE                                                     v_estagio := v_atual;
  END IF;

  INSERT INTO crm_atendimentos AS t
    (chat_id, telefone, lid, nome_whatsapp, estagio, idioma, ultima_mensagem, ultima_direcao,
     total_entrada, total_saida, ultimo_contato, atualizado_em, responsavel)
  VALUES
    (v_alvo, v_tel, v_lid, v_nome, v_estagio,
     (SELECT i.idioma FROM cliente_idioma i WHERE i.chat_id = v_alvo),
     left(coalesce(p_texto,''),500), v_direcao,
     CASE WHEN v_direcao='entrada' THEN 1 ELSE 0 END,
     CASE WHEN v_direcao='saida'   THEN 1 ELSE 0 END,
     now(), now(),
     CASE WHEN v_origem='humano' THEN 'atendente' ELSE NULL END)
  ON CONFLICT (chat_id) DO UPDATE SET
    telefone        = coalesce(v_tel, t.telefone),
    lid             = coalesce(v_lid, t.lid),
    nome_whatsapp   = coalesce(v_nome, t.nome_whatsapp),
    estagio         = v_estagio,
    idioma          = coalesce((SELECT i.idioma FROM cliente_idioma i WHERE i.chat_id = v_alvo), t.idioma),
    ultima_mensagem = left(coalesce(p_texto,''),500),
    ultima_direcao  = v_direcao,
    total_entrada   = t.total_entrada + CASE WHEN v_direcao='entrada' THEN 1 ELSE 0 END,
    total_saida     = t.total_saida   + CASE WHEN v_direcao='saida'   THEN 1 ELSE 0 END,
    ultimo_contato  = now(),
    atualizado_em   = now(),
    responsavel     = CASE WHEN v_origem='humano' THEN 'atendente' ELSE t.responsavel END;

  INSERT INTO crm_mensagens (chat_id, direcao, origem, texto, eh_audio)
  VALUES (v_alvo, v_direcao, v_origem, p_texto, coalesce(p_eh_audio,false));

  PERFORM crm_reconciliar(v_alvo);
  RETURN (SELECT estagio FROM crm_atendimentos WHERE chat_id = v_alvo);
END;
$$;


--
-- Name: crm_relatorio(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.crm_relatorio(p_tipo text, p_dias integer DEFAULT 30) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  v_tz  text := 'America/Sao_Paulo';
  v_d   int  := greatest(1, least(coalesce(p_dias,30), 365));
  v_ini timestamptz := now() - make_interval(days => v_d);
BEGIN
  IF p_tipo = 'conversas' THEN
    RETURN jsonb_build_object('ok', true, 'tipo', p_tipo, 'dias', v_d,
      'colunas', jsonb_build_array('telefone','estagio','idioma','responsavel',
                                   'recebidas','enviadas','primeiro_contato','ultimo_contato','notas'),
      'linhas', (SELECT coalesce(jsonb_agg(jsonb_build_array(
                    crm_contato_rotulo(c.chat_id), c.estagio, coalesce(c.idioma,''), coalesce(c.responsavel,''),
                    c.total_entrada, c.total_saida,
                    to_char(c.primeiro_contato AT TIME ZONE v_tz,'DD/MM/YYYY HH24:MI'),
                    to_char(c.ultimo_contato   AT TIME ZONE v_tz,'DD/MM/YYYY HH24:MI'),
                    coalesce(c.notas,'')) ORDER BY c.ultimo_contato DESC), '[]'::jsonb)
                  FROM crm_atendimentos c WHERE c.ultimo_contato >= v_ini));

  ELSIF p_tipo = 'mensagens' THEN
    RETURN jsonb_build_object('ok', true, 'tipo', p_tipo, 'dias', v_d,
      'colunas', jsonb_build_array('quando','telefone','direcao','origem','texto'),
      'linhas', (SELECT coalesce(jsonb_agg(jsonb_build_array(
                    to_char(m.criado_em AT TIME ZONE v_tz,'DD/MM/YYYY HH24:MI'),
                    crm_contato_rotulo(m.chat_id), m.direcao, m.origem,
                    coalesce(m.texto, CASE WHEN m.eh_audio THEN '[audio]' ELSE '' END))
                    ORDER BY m.criado_em DESC), '[]'::jsonb)
                  FROM crm_mensagens m WHERE m.criado_em >= v_ini));

  ELSIF p_tipo = 'treinamentos' THEN
    RETURN jsonb_build_object('ok', true, 'tipo', p_tipo, 'dias', v_d,
      'colunas', jsonb_build_array('quando','telefone','situacao','marcado_em','observacao'),
      'linhas', (SELECT coalesce(jsonb_agg(jsonb_build_array(
                    to_char(a.inicio AT TIME ZONE v_tz,'DD/MM/YYYY HH24:MI'),
                    crm_contato_rotulo(a.chat_id), a.status,
                    to_char(a.criado_em AT TIME ZONE v_tz,'DD/MM/YYYY HH24:MI'),
                    coalesce(a.observacao,'')) ORDER BY a.inicio DESC), '[]'::jsonb)
                  FROM agendamentos_treinamento a
                 WHERE a.inicio >= v_ini OR a.criado_em >= v_ini));

  ELSIF p_tipo = 'agenda' THEN
    RETURN jsonb_build_object('ok', true, 'tipo', p_tipo,
      'colunas', jsonb_build_array('quando','telefone','marcado_em'),
      'linhas', (SELECT coalesce(jsonb_agg(jsonb_build_array(
                    agenda_rotulo(a.inicio), crm_contato_rotulo(a.chat_id),
                    to_char(a.criado_em AT TIME ZONE v_tz,'DD/MM HH24:MI')) ORDER BY a.inicio), '[]'::jsonb)
                  FROM agendamentos_treinamento a
                 WHERE a.status='confirmado' AND a.inicio > now()));
  END IF;
  RETURN jsonb_build_object('ok', false, 'erro','TIPO_DESCONHECIDO');
END;
$$;


--
-- Name: crm_senha_trocar(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.crm_senha_trocar(p_usuario text, p_atual text, p_nova text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE v_hash text;
BEGIN
  SELECT senha_hash INTO v_hash FROM crm_usuarios WHERE usuario = lower(trim(coalesce(p_usuario,'')));
  IF v_hash IS NULL OR v_hash <> crypt(coalesce(p_atual,''), v_hash) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'CREDENCIAL_INVALIDA');
  END IF;
  IF p_nova IS NULL OR length(p_nova) < 8 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'SENHA_CURTA');
  END IF;
  UPDATE crm_usuarios SET senha_hash = crypt(p_nova, gen_salt('bf', 10))
   WHERE usuario = lower(trim(p_usuario));
  DELETE FROM crm_sessoes WHERE usuario = lower(trim(p_usuario));
  RETURN jsonb_build_object('ok', true);
END; $$;


--
-- Name: crm_sessao_usuario(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.crm_sessao_usuario(p_token text) RETURNS text
    LANGUAGE sql
    AS $$
  UPDATE crm_sessoes SET expira_em = now() + interval '12 hours'
   WHERE token = nullif(p_token,'') AND expira_em > now()
   RETURNING usuario;
$$;


--
-- Name: crm_trg_agenda(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.crm_trg_agenda() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.status = 'confirmado' THEN
    UPDATE crm_atendimentos SET estagio='treinamento_agendado', atualizado_em=now()
     WHERE chat_id = NEW.chat_id;
  ELSIF NEW.status = 'cancelado' THEN
    UPDATE crm_atendimentos SET estagio='bot_atendendo', atualizado_em=now()
     WHERE chat_id = NEW.chat_id AND estagio = 'treinamento_agendado';
  END IF;
  RETURN NEW;
END; $$;


--
-- Name: crm_trg_idioma(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.crm_trg_idioma() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE crm_atendimentos SET idioma = NEW.idioma, atualizado_em = now()
   WHERE chat_id = NEW.chat_id;
  RETURN NEW;
END; $$;


--
-- Name: crm_trg_pausa(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.crm_trg_pausa() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE crm_atendimentos SET
    estagio = CASE WHEN NEW.motivo ILIKE 'Cliente pediu%' THEN 'aguardando_humano' ELSE 'em_atendimento' END,
    atualizado_em = now()
  WHERE chat_id = NEW.chat_id;
  RETURN NEW;
END; $$;


--
-- Name: crm_usuario_criar(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.crm_usuario_criar(p_usuario text, p_senha text, p_nome text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF p_usuario IS NULL OR length(trim(p_usuario)) < 3 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'USUARIO_CURTO');
  END IF;
  IF p_senha IS NULL OR length(p_senha) < 8 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'SENHA_CURTA');
  END IF;
  INSERT INTO crm_usuarios (usuario, senha_hash, nome)
  VALUES (lower(trim(p_usuario)), crypt(p_senha, gen_salt('bf', 10)), nullif(trim(coalesce(p_nome,'')),''));
  RETURN jsonb_build_object('ok', true, 'usuario', lower(trim(p_usuario)));
EXCEPTION WHEN unique_violation THEN
  RETURN jsonb_build_object('ok', false, 'erro', 'USUARIO_EXISTE');
END; $$;


--
-- Name: pausa_ativa(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pausa_ativa(p_chat text) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM pausa_humana p, crm_parametros c
     WHERE c.id = 1
       AND p.chat_id = p_chat
       AND p.pausado_em > now() - make_interval(mins => c.pausa_minutos));
$$;


--
-- Name: pausa_minutos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pausa_minutos() RETURNS integer
    LANGUAGE sql STABLE
    AS $$
  SELECT pausa_minutos FROM crm_parametros WHERE id = 1;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: agenda_bloqueios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agenda_bloqueios (
    dia date NOT NULL,
    motivo text
);


--
-- Name: agenda_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agenda_config (
    id integer DEFAULT 1 NOT NULL,
    hora_inicio integer DEFAULT 13 NOT NULL,
    hora_fim integer DEFAULT 22 NOT NULL,
    duracao_min integer DEFAULT 60 NOT NULL,
    antecedencia_min integer DEFAULT 120 NOT NULL,
    horizonte_dias integer DEFAULT 21 NOT NULL,
    fuso text DEFAULT 'America/Sao_Paulo'::text NOT NULL,
    CONSTRAINT agenda_config_id_check CHECK ((id = 1))
);


--
-- Name: agendamentos_treinamento; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agendamentos_treinamento (
    id bigint NOT NULL,
    chat_id text NOT NULL,
    nome_cliente text,
    inicio timestamp with time zone NOT NULL,
    fim timestamp with time zone NOT NULL,
    status text DEFAULT 'confirmado'::text NOT NULL,
    observacao text,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    lembrete_em timestamp with time zone,
    CONSTRAINT agendamentos_treinamento_status_check CHECK ((status = ANY (ARRAY['confirmado'::text, 'cancelado'::text, 'realizado'::text])))
);


--
-- Name: agendamentos_treinamento_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.agendamentos_treinamento_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: agendamentos_treinamento_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.agendamentos_treinamento_id_seq OWNED BY public.agendamentos_treinamento.id;


--
-- Name: audios_enviados; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audios_enviados (
    id bigint NOT NULL,
    chat_id text NOT NULL,
    audio text NOT NULL,
    enviado_em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: audios_enviados_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.audios_enviados_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audios_enviados_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.audios_enviados_id_seq OWNED BY public.audios_enviados.id;


--
-- Name: cliente_idioma; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cliente_idioma (
    chat_id text NOT NULL,
    idioma text DEFAULT 'pt'::text NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: crm_atendimentos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.crm_atendimentos (
    chat_id text NOT NULL,
    telefone text,
    nome text,
    estagio text DEFAULT 'novo'::text NOT NULL,
    idioma text,
    responsavel text,
    tags text[] DEFAULT '{}'::text[] NOT NULL,
    notas text,
    ultima_mensagem text,
    ultima_direcao text,
    total_entrada integer DEFAULT 0 NOT NULL,
    total_saida integer DEFAULT 0 NOT NULL,
    primeiro_contato timestamp with time zone DEFAULT now() NOT NULL,
    ultimo_contato timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    lid text,
    nome_whatsapp text,
    movido_em timestamp with time zone
);


--
-- Name: crm_estagios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.crm_estagios (
    estagio text NOT NULL,
    titulo text NOT NULL,
    ordem integer NOT NULL,
    cor text DEFAULT '#64748b'::text NOT NULL,
    cor_escura text
);


--
-- Name: crm_mensagens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.crm_mensagens (
    id bigint NOT NULL,
    chat_id text NOT NULL,
    direcao text NOT NULL,
    origem text NOT NULL,
    texto text,
    eh_audio boolean DEFAULT false NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT crm_mensagens_direcao_check CHECK ((direcao = ANY (ARRAY['entrada'::text, 'saida'::text]))),
    CONSTRAINT crm_mensagens_origem_check CHECK ((origem = ANY (ARRAY['cliente'::text, 'bot'::text, 'humano'::text])))
);


--
-- Name: crm_mensagens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.crm_mensagens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: crm_mensagens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.crm_mensagens_id_seq OWNED BY public.crm_mensagens.id;


--
-- Name: crm_parametros; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.crm_parametros (
    id integer DEFAULT 1 NOT NULL,
    pausa_minutos integer DEFAULT 75 NOT NULL,
    CONSTRAINT crm_parametros_id_check CHECK ((id = 1))
);


--
-- Name: crm_sessoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.crm_sessoes (
    token text NOT NULL,
    usuario text NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    expira_em timestamp with time zone DEFAULT (now() + '12:00:00'::interval) NOT NULL
);


--
-- Name: crm_usuarios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.crm_usuarios (
    usuario text NOT NULL,
    senha_hash text NOT NULL,
    nome text,
    ativo boolean DEFAULT true NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    ultimo_acesso timestamp with time zone
);


--
-- Name: n8n_chat_histories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.n8n_chat_histories (
    id integer NOT NULL,
    session_id character varying(255) NOT NULL,
    message jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: n8n_chat_histories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.n8n_chat_histories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: n8n_chat_histories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.n8n_chat_histories_id_seq OWNED BY public.n8n_chat_histories.id;


--
-- Name: pausa_humana; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pausa_humana (
    chat_id text NOT NULL,
    motivo text,
    pausado_em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: agendamentos_treinamento id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agendamentos_treinamento ALTER COLUMN id SET DEFAULT nextval('public.agendamentos_treinamento_id_seq'::regclass);


--
-- Name: audios_enviados id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audios_enviados ALTER COLUMN id SET DEFAULT nextval('public.audios_enviados_id_seq'::regclass);


--
-- Name: crm_mensagens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_mensagens ALTER COLUMN id SET DEFAULT nextval('public.crm_mensagens_id_seq'::regclass);


--
-- Name: n8n_chat_histories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.n8n_chat_histories ALTER COLUMN id SET DEFAULT nextval('public.n8n_chat_histories_id_seq'::regclass);


--
-- Name: agenda_bloqueios agenda_bloqueios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agenda_bloqueios
    ADD CONSTRAINT agenda_bloqueios_pkey PRIMARY KEY (dia);


--
-- Name: agenda_config agenda_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agenda_config
    ADD CONSTRAINT agenda_config_pkey PRIMARY KEY (id);


--
-- Name: agendamentos_treinamento agendamentos_treinamento_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agendamentos_treinamento
    ADD CONSTRAINT agendamentos_treinamento_pkey PRIMARY KEY (id);


--
-- Name: audios_enviados audios_enviados_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audios_enviados
    ADD CONSTRAINT audios_enviados_pkey PRIMARY KEY (id);


--
-- Name: cliente_idioma cliente_idioma_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cliente_idioma
    ADD CONSTRAINT cliente_idioma_pkey PRIMARY KEY (chat_id);


--
-- Name: crm_atendimentos crm_atendimentos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_atendimentos
    ADD CONSTRAINT crm_atendimentos_pkey PRIMARY KEY (chat_id);


--
-- Name: crm_estagios crm_estagios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_estagios
    ADD CONSTRAINT crm_estagios_pkey PRIMARY KEY (estagio);


--
-- Name: crm_mensagens crm_mensagens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_mensagens
    ADD CONSTRAINT crm_mensagens_pkey PRIMARY KEY (id);


--
-- Name: crm_parametros crm_parametros_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_parametros
    ADD CONSTRAINT crm_parametros_pkey PRIMARY KEY (id);


--
-- Name: crm_sessoes crm_sessoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_sessoes
    ADD CONSTRAINT crm_sessoes_pkey PRIMARY KEY (token);


--
-- Name: crm_usuarios crm_usuarios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_usuarios
    ADD CONSTRAINT crm_usuarios_pkey PRIMARY KEY (usuario);


--
-- Name: n8n_chat_histories n8n_chat_histories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.n8n_chat_histories
    ADD CONSTRAINT n8n_chat_histories_pkey PRIMARY KEY (id);


--
-- Name: pausa_humana pausa_humana_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pausa_humana
    ADD CONSTRAINT pausa_humana_pkey PRIMARY KEY (chat_id);


--
-- Name: idx_agenda_chat; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agenda_chat ON public.agendamentos_treinamento USING btree (chat_id, inicio DESC);


--
-- Name: idx_audios_enviados_chat_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audios_enviados_chat_data ON public.audios_enviados USING btree (chat_id, enviado_em DESC);


--
-- Name: idx_chat_hist_session_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_hist_session_data ON public.n8n_chat_histories USING btree (session_id, created_at DESC);


--
-- Name: idx_crm_estagio; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_crm_estagio ON public.crm_atendimentos USING btree (estagio, ultimo_contato DESC);


--
-- Name: idx_crm_msg_chat; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_crm_msg_chat ON public.crm_mensagens USING btree (chat_id, criado_em DESC);


--
-- Name: idx_crm_sessoes_exp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_crm_sessoes_exp ON public.crm_sessoes USING btree (expira_em);


--
-- Name: idx_pausa_humana_pausado_em; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pausa_humana_pausado_em ON public.pausa_humana USING btree (pausado_em DESC);


--
-- Name: uniq_agenda_slot; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uniq_agenda_slot ON public.agendamentos_treinamento USING btree (inicio) WHERE (status = 'confirmado'::text);


--
-- Name: agendamentos_treinamento trg_crm_agenda; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_crm_agenda AFTER INSERT OR UPDATE ON public.agendamentos_treinamento FOR EACH ROW EXECUTE FUNCTION public.crm_trg_agenda();


--
-- Name: cliente_idioma trg_crm_idioma; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_crm_idioma AFTER INSERT OR UPDATE ON public.cliente_idioma FOR EACH ROW EXECUTE FUNCTION public.crm_trg_idioma();


--
-- Name: pausa_humana trg_crm_pausa; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_crm_pausa AFTER INSERT OR UPDATE ON public.pausa_humana FOR EACH ROW EXECUTE FUNCTION public.crm_trg_pausa();


--
-- Name: crm_sessoes crm_sessoes_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_sessoes
    ADD CONSTRAINT crm_sessoes_usuario_fkey FOREIGN KEY (usuario) REFERENCES public.crm_usuarios(usuario) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--


