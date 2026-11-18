-- Configuracao inicial. Ajuste a vontade depois da primeira subida.

-- Janela de agendamento: das 13h as 22h, 60 min cada, minimo 120 min de
-- antecedencia, ate 21 dias a frente, no fuso de Sao Paulo.
INSERT INTO agenda_config (id, hora_inicio, hora_fim, duracao_min, antecedencia_min, horizonte_dias, fuso)
VALUES (1, 13, 22, 60, 120, 21, 'America/Sao_Paulo')
ON CONFLICT (id) DO NOTHING;

-- Colunas do Kanban do painel.
INSERT INTO crm_estagios (estagio, titulo, ordem, cor, cor_escura) VALUES
  ('novo',                 'Novos',          1, '#1d4ed8', '#3b82f6'),
  ('bot_atendendo',        'Bot atendendo',  2, '#0891b2', '#14b8a6'),
  ('aguardando_humano',    'Fila do humano', 3, '#d97706', '#d9810a'),
  ('em_atendimento',       'Em atendimento', 4, '#be185d', '#ec4899'),
  ('treinamento_agendado', 'Agendado',       5, '#166534', '#16a34a'),
  ('resolvido',            'Resolvido',      6, '#64748b', '#78899b')
ON CONFLICT DO NOTHING;

-- Quantos minutos o bot fica pausado depois que um humano responde.
INSERT INTO crm_parametros (id, pausa_minutos) VALUES (1, 75)
ON CONFLICT (id) DO NOTHING;
