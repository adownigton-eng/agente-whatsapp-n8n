/* =====================================================================
   Painel CRM v6
   Mesmo contrato de API da v5 (/api/crm-api e /api/crm-conexao): nada
   muda no n8n nem no banco. Organizado por secoes: utilitarios, API,
   acesso, navegacao, kanban, gaveta, dashboard, agenda, relatorios,
   conexao, equipe e inicio.
   ===================================================================== */
(function(){
'use strict';

/* ==================== utilitarios ==================== */
var token = '';
try { token = localStorage.getItem('crm_sessao') || ''; } catch(e) {}
var dados = {cards:[], estagios:[], agenda:[]};
var vista = 'kanban', atual = null, arrastando = false, modoSetup = false;
var usuarioAtual = '';
var filtro = 'todas', verTodasResolvidas = false;

function $(s){ return document.querySelector(s); }
function esc(s){ return String(s == null ? '' : s).replace(/[&<>"']/g, function(c){
  return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]; }); }
function ls(k, v){
  try { if(v === undefined) return localStorage.getItem(k);
        if(v === null) localStorage.removeItem(k); else localStorage.setItem(k, v); }
  catch(e) { return null; }
}

/* Aviso (toast). Com `acao`, mostra um botao (ex.: Desfazer) e fica mais tempo. */
function aviso(msg, acao){
  var t = $('#aviso'), b = $('#avisoAcao');
  $('#avisoTxt').textContent = msg;
  b.hidden = !acao;
  if(acao){ b.textContent = acao.rotulo; b.onclick = function(){ t.classList.remove('on'); acao.fn(); }; }
  t.classList.add('on');
  clearTimeout(aviso._t);
  aviso._t = setTimeout(function(){ t.classList.remove('on'); }, acao ? 7000 : 3200);
}

/* Tema: segue o sistema; o botao alterna e lembra a escolha. */
(function(){ var t = ls('crm_tema'); if(t) document.documentElement.dataset.theme = t; })();
function alternarTema(){
  var r = document.documentElement;
  var escuro = r.dataset.theme ? r.dataset.theme === 'dark'
                               : matchMedia('(prefers-color-scheme: dark)').matches;
  r.dataset.theme = escuro ? 'light' : 'dark';
  ls('crm_tema', r.dataset.theme);
}

/* Botao ocupado durante a acao: evita clique duplo e mostra que algo acontece. */
async function ocupado(btn, texto, fn){
  if(btn.disabled) return;
  var orig = btn.textContent;
  btn.disabled = true; btn.setAttribute('aria-busy', 'true');
  if(texto) btn.textContent = texto;
  try { return await fn(); }
  finally { btn.disabled = false; btn.removeAttribute('aria-busy'); btn.textContent = orig; }
}

/* Bloco de estado padrao: carregando, erro (com tentar de novo) ou vazio. */
function estado(alvo, tipo, titulo, texto, tentar){
  var ponto = {erro:'risco', vazio:'', carregando:'acao'}[tipo] || '';
  alvo.innerHTML = '<div class="bloco estado"><div class="titulo-estado"><span class="ponto ' + ponto +
    '" aria-hidden="true"></span><h3>' + esc(titulo) + '</h3></div>' +
    (texto ? '<p>' + esc(texto) + '</p>' : '') +
    (tentar ? '<button class="b pri" type="button">Tentar de novo</button>' : '') + '</div>';
  if(tentar) alvo.querySelector('button').onclick = tentar;
}

/* ==================== contato ==================== */
var DDI = ['55','1','52','54','56','57','51','58','591','593','595','598','502','503','504',
           '505','506','507','34','351','39','44','49','33'];
function foneFmt(t){
  var d = String(t || '').replace(/\D/g, '');
  if(!d) return '';
  if(d.indexOf('55') === 0 && (d.length === 12 || d.length === 13)){
    var ddd = d.substr(2,2), n = d.substr(4);
    return '+55 (' + ddd + ') ' + n.substr(0, n.length-4) + '-' + n.substr(-4);
  }
  var cc = DDI.filter(function(c){ return d.indexOf(c) === 0; })
              .sort(function(a,b){ return b.length - a.length; })[0] || '';
  var resto = d.substr(cc.length);
  var blocos = resto.length > 7 ? [resto.slice(0,-7), resto.slice(-7,-4), resto.slice(-4)]
                                : [resto.slice(0,-4), resto.slice(-4)];
  return '+' + (cc ? cc + ' ' : '') + blocos.filter(Boolean).join(' ');
}
function nomeDe(c){ return (c.nome || c.nome_whatsapp || '').trim(); }
function identificado(c){ return !!(nomeDe(c) || c.telefone); }
function idWhats(c){ return String(c.lid || String(c.chat_id || '').split('@')[0] || '').replace(/\D/g, ''); }
function contatoTitulo(c){ return nomeDe(c) || foneFmt(c.telefone) || idWhats(c) || 'Contato'; }
function contatoSub(c){
  if(c.telefone) return nomeDe(c) ? foneFmt(c.telefone) : '';
  return nomeDe(c) ? idWhats(c) + ' · ID do WhatsApp' : 'ID do WhatsApp · número oculto';
}
function iniciais(c){
  var n = nomeDe(c).replace(/[^\p{L}\p{N} ]/gu, ' ').trim().split(/\s+/).filter(Boolean);
  if(n.length) return ((n[0][0] || '') + (n.length > 1 ? n[n.length-1][0] : '')).toUpperCase();
  var d = String(c.telefone || '').replace(/\D/g, '') || idWhats(c);
  return d ? d.slice(-2) : '?';
}
function avatarHtml(c, grande){
  var h = 0, s = String(c.chat_id || '');
  for(var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 360;
  return '<span class="av' + (grande ? ' g' : '') + (identificado(c) ? '' : ' oculto') +
         '" style="--h:' + h + '" aria-hidden="true">' + esc(iniciais(c)) + '</span>';
}
function idade(min){
  if(min == null) return '';
  if(min < 1) return 'agora';
  if(min < 60) return min + ' min';
  if(min < 1440) return Math.floor(min/60) + ' h';
  return Math.floor(min/1440) + ' d';
}
function idadeLonga(min){
  if(min == null) return '-';
  if(min < 1) return 'agora mesmo';
  return 'há ' + idade(min);
}

/* ==================== vocabulario unico ==================== */
/* Rotulos de etapa vem do banco; aqui so normalizamos para a linguagem do
   painel. Etapa desconhecida cai no titulo que veio do banco. */
var ETAPA = {
  novo:'Novas', bot_atendendo:'Bot atendendo', aguardando_humano:'Aguardando atendente',
  em_atendimento:'Em atendimento', treinamento_agendado:'Treinamento agendado', resolvido:'Resolvidas'
};
function etapaRotulo(cod){
  if(ETAPA[cod]) return ETAPA[cod];
  var e = (dados.estagios || []).find(function(x){ return x.estagio === cod; });
  return e ? e.titulo : (cod || '-');
}
var IDIOMA = {pt:'Português', es:'Espanhol', en:'Inglês'};

/* ==================== API ==================== */
var ERROS = {
  CREDENCIAL_INVALIDA:'Usuário ou senha incorretos.',
  SENHA_CURTA:'A senha precisa ter pelo menos 8 caracteres.',
  USUARIO_CURTO:'O usuário precisa ter pelo menos 3 caracteres.',
  USUARIO_EXISTE:'Esse usuário já existe.',
  JA_CONFIGURADO:'O painel já tem usuários. Entre com o seu acesso.',
  ESTAGIO_INVALIDO:'Essa etapa não existe mais. Atualize a página.',
  TIMEOUT:'O servidor demorou para responder. Tente de novo.',
  REDE:'Sem conexão com o servidor. Confira a internet.',
  'HTTP 502':'O servidor está reiniciando. Tente em instantes.',
  'HTTP 503':'O servidor está reiniciando. Tente em instantes.',
  'HTTP 504':'O servidor demorou para responder. Tente de novo.',
  'HTTP 500':'Erro no servidor. Se continuar, avise o suporte.'
};
function texto(e){ return ERROS[e && e.message] || (e && e.message) || 'Erro desconhecido'; }

async function chamar(rota, acao, extra){
  var ctl = new AbortController();
  var t = setTimeout(function(){ ctl.abort(); }, 15000);
  var r;
  try {
    r = await fetch('/api/' + rota, {method:'POST', signal:ctl.signal,
      headers:{'Content-Type':'application/json'},
      body: JSON.stringify(Object.assign({acao:acao, token:token}, extra || {}))});
  } catch(e){
    throw new Error(e.name === 'AbortError' ? 'TIMEOUT' : 'REDE');
  } finally { clearTimeout(t); }
  if(!r.ok) throw new Error('HTTP ' + r.status);
  var j = await r.json();
  if(j && j.ok === false){
    if(j.erro === 'SESSAO_INVALIDA'){ sessaoExpirou(); throw new Error('sessao'); }
    throw new Error(j.erro || 'erro');
  }
  return j;
}
function api(acao, extra){ return chamar('crm-api', acao, extra); }
function conexao(acao){ return chamar('crm-conexao', acao); }
function falhou(e, oque){ if(e.message !== 'sessao') aviso(oque + ': ' + texto(e)); }

/* Cache curto: telas de consulta nao refazem a mesma pergunta em 60s. */
var cache = {};
async function comCache(chave, fn, forcar){
  var c = cache[chave];
  if(!forcar && c && Date.now() - c.quando < 60000) return c.dados;
  var d = await fn();
  cache[chave] = {quando:Date.now(), dados:d};
  return d;
}

/* ==================== acesso ==================== */
function guardar(t){ token = t || ''; ls('crm_sessao', token || null); }
function sessaoExpirou(){
  guardar('');
  fechar(true);
  mostrarAcesso('Sua sessão expirou. Entre de novo para continuar.');
}
async function mostrarAcesso(motivo){
  $('#app').hidden = true; $('#acesso').classList.add('on');
  $('#acErro').textContent = motivo || '';
  try { modoSetup = !!(await api('status')).precisa_setup; } catch(e) { modoSetup = false; }
  $('#acTitulo').textContent = modoSetup ? 'Primeiro acesso' : 'Entrar';
  $('#acTexto').textContent = modoSetup
    ? 'Nenhum usuário cadastrado. Crie o acesso do administrador (senha com 8 caracteres ou mais).'
    : 'Use o usuário e a senha da sua equipe.';
  $('#acBotao').textContent = modoSetup ? 'Criar acesso' : 'Entrar';
  $('#acNome').hidden = !modoSetup;
  $('#acUsuario').focus();
}
$('#acBotao').onclick = function(){
  var btn = this;
  $('#acErro').textContent = '';
  var u = $('#acUsuario').value.trim(), s = $('#acSenha').value;
  if(!u || !s){ $('#acErro').textContent = 'Preencha usuário e senha.'; return; }
  ocupado(btn, modoSetup ? 'Criando...' : 'Entrando...', async function(){
    try {
      var r = await api(modoSetup ? 'primeiro_acesso' : 'login',
                        {usuario:u, senha:s, nome:$('#acNomeInput').value.trim()});
      guardar(r.token); $('#acSenha').value = '';
      $('#acesso').classList.remove('on'); $('#app').hidden = false;
      identificar(r.nome || r.usuario, r.usuario);
      navegar(vista);
      carregar(true);
    } catch(e){ $('#acErro').textContent = texto(e); }
  });
};
$('#acSenha').addEventListener('keydown', function(e){ if(e.key === 'Enter') $('#acBotao').click(); });
$('#acUsuario').addEventListener('keydown', function(e){ if(e.key === 'Enter') $('#acSenha').focus(); });
async function sair(){
  try { await api('logout'); } catch(e) {}
  guardar(''); fechar(true); mostrarAcesso();
}
$('#btSair').onclick = sair;
$('#btTema').onclick = alternarTema;
function identificar(nome, usuario){
  if(usuario) usuarioAtual = usuario;
  $('#quem').textContent = nome || '';
  $('#ini').textContent = (nome || '?').trim().charAt(0).toUpperCase();
}

/* ==================== navegacao ==================== */
var TITULOS = {kanban:'Kanban', dashboard:'Dashboard', agenda:'Agenda',
               relatorios:'Relatórios', conexao:'Conexão do WhatsApp', equipe:'Equipe e conta'};
document.querySelectorAll('.nv').forEach(function(b){
  b.onclick = function(){ navegar(b.dataset.v); };
});
function navegar(v){
  vista = v;
  document.querySelectorAll('.nv').forEach(function(b){
    if(b.dataset.v === v) b.setAttribute('aria-current', 'page'); else b.removeAttribute('aria-current');
  });
  Object.keys(TITULOS).forEach(function(x){ $('#v-' + x).hidden = (x !== v); });
  $('#titulo').textContent = TITULOS[v];
  $('#acoesTopo').innerHTML = '';
  $('#sub').textContent = '';
  if(v === 'kanban')     { acoesKanban(); desenhar(true); }
  if(v === 'dashboard')  { acoesDash(); carregarDash(); }
  if(v === 'agenda')     carregarAgenda();
  if(v === 'relatorios') desenharRelatorios();
  if(v === 'conexao')    carregarConexao(true);
  if(v === 'equipe')     carregarEquipe();
  agendarConexao();
}

/* ==================== kanban ==================== */
/* Conversa "esperando resposta": a ultima mensagem foi do cliente e ela nao
   esta resolvida. E o que o dono precisa ver primeiro. */
function esperando(c){
  return c.ultima_direcao === 'entrada' && c.estagio !== 'resolvido' && c.minutos != null;
}
function nivelEspera(c){
  if(!esperando(c)) return '';
  if(c.minutos >= 30) return 'urgente';
  if(c.minutos >= 10) return 'espera';
  return '';
}
function precisaAtencao(c){ return c.estagio === 'aguardando_humano' || nivelEspera(c) !== ''; }

function preparar(cards){
  cards.forEach(function(c){
    c._busca = [c.nome, c.nome_whatsapp, c.telefone, foneFmt(c.telefone), c.lid, c.ultima_mensagem]
      .join(' ').toLowerCase();
    c._fone = String(c.telefone || '');
  });
}

var FILTROS = [
  {id:'todas',    rot:'Todas',               f:function(){ return true; }},
  {id:'atencao',  rot:'Precisam de resposta', f:precisaAtencao},
  {id:'pausado',  rot:'Bot pausado',          f:function(c){ return !!c.pausado; }},
  {id:'comigo',   rot:'Comigo',               f:function(c){ return usuarioAtual && c.responsavel === usuarioAtual; }}
];
function acoesKanban(){
  $('#acoesTopo').innerHTML =
    '<label class="sr-only" for="busca">Buscar conversas</label>' +
    '<input class="campo" type="search" id="busca" placeholder="Buscar por nome, telefone ou mensagem" enterkeyhint="search">';
  var t;
  $('#busca').oninput = function(){ clearTimeout(t); t = setTimeout(function(){ desenhar(true); }, 200); };
}
function desenharFiltros(){
  $('#filtros').innerHTML = FILTROS.map(function(x){
    var n = dados.cards.filter(x.f).length;
    return '<button class="chip" type="button" data-f="' + x.id + '" aria-pressed="' + (filtro === x.id) + '">' +
      esc(x.rot) + '<span class="num">' + n + '</span></button>';
  }).join('');
}
$('#filtros').addEventListener('click', function(e){
  var b = e.target.closest('.chip'); if(!b) return;
  filtro = b.dataset.f; ls('crm_filtro', filtro); desenhar(true);
});
(function(){ var f = ls('crm_filtro'); if(f && FILTROS.some(function(x){ return x.id === f; })) filtro = f; })();

function cardHtml(c){
  var t = [], n = nivelEspera(c);
  if(n) t.push('<span class="tag ' + (n === 'urgente' ? 'tag-risco' : 'tag-alerta') +
                '">Aguardando resposta há ' + esc(idade(c.minutos)) + '</span>');
  if(c.pausado)     t.push('<span class="tag tag-risco">Bot pausado</span>');
  if(c.responsavel) t.push('<span class="tag tag-acao">Resp.: ' + esc(c.responsavel) + '</span>');
  if(c.treinamento) t.push('<span class="tag tag-ok">Trein.: ' + esc(c.treinamento) + '</span>');
  if(c.idioma && c.idioma !== 'pt') t.push('<span class="tag">' + esc(IDIOMA[c.idioma] || c.idioma) + '</span>');
  var quem = c.ultima_direcao === 'saida' ? 'Resposta' : 'Cliente';
  var titulo = contatoTitulo(c);
  return '<article class="card' + (n ? ' ' + n : '') + (novos[c.chat_id] ? ' novo-flash' : '') +
    '" draggable="true" tabindex="0" role="button" aria-haspopup="dialog" data-chat="' + esc(c.chat_id) +
    '" aria-label="' + esc(titulo + ', ' + etapaRotulo(c.estagio)) + '">' +
    '<header class="card-id">' + avatarHtml(c) +
      '<div class="card-nome"><strong class="' + (identificado(c) ? '' : 'oculto') + '">' + esc(titulo) + '</strong>' +
        (contatoSub(c) ? '<span class="card-meta">' + esc(contatoSub(c)) + '</span>' : '') + '</div>' +
      '<time class="card-tempo" title="Último contato ' + esc(idadeLonga(c.minutos)) + '">' +
        esc(idade(c.minutos)) + '</time></header>' +
    '<p class="card-msg">' + (c.ultima_mensagem ? '<b>' + quem + ':</b> ' + esc(c.ultima_mensagem)
                                                : 'Sem mensagens ainda') + '</p>' +
    (t.length ? '<footer class="tags">' + t.join('') + '</footer>' : '') + '</article>';
}

var assinaturaQuadro = '', novos = {}, conhecidos = null;
function desenhar(forcar){
  if(vista !== 'kanban') return;
  var bu = $('#busca'), q = bu ? bu.value.trim().toLowerCase() : '', qd = q.replace(/\D/g, '');
  var fx = (FILTROS.find(function(x){ return x.id === filtro; }) || FILTROS[0]).f;
  var cards = dados.cards.filter(function(c){
    return fx(c) && (!q || c._busca.indexOf(q) >= 0 || (qd.length >= 3 && c._fone.indexOf(qd) >= 0));
  });
  var assinatura = JSON.stringify([q, filtro, verTodasResolvidas, dados.estagios, dados.cards]);
  if(!forcar && assinatura === assinaturaQuadro) return;
  assinaturaQuadro = assinatura;

  desenharFiltros();
  var rolagem = $('#quadro').scrollLeft;
  $('#quadro').innerHTML = dados.estagios.map(function(e){
    var meus = cards.filter(function(c){ return c.estagio === e.estagio; });
    var ocultos = 0;
    // Resolvidas so cresce: por padrao mostra a ultima semana.
    if(e.estagio === 'resolvido' && !verTodasResolvidas){
      var recentes = meus.filter(function(c){ return c.minutos == null || c.minutos <= 7 * 1440; });
      ocultos = meus.length - recentes.length; meus = recentes;
    }
    return '<section class="col" aria-label="' + esc(etapaRotulo(e.estagio)) + '">' +
      '<div class="colh"><span class="pt" style="--c:' + esc(e.cor) + '" aria-hidden="true"></span>' +
      '<span class="colt">' + esc(etapaRotulo(e.estagio)) + '</span>' +
      '<span class="cnt">' + (meus.length + ocultos) + '</span></div>' +
      '<div class="drop" data-estagio="' + esc(e.estagio) + '">' +
      (meus.length ? meus.map(cardHtml).join('') : '<div class="vazio">Nenhuma conversa nesta etapa</div>') +
      (ocultos ? '<button class="mais" type="button" data-mais="1">Ver mais ' + ocultos + ' antigas</button>' : '') +
      '</div></section>';
  }).join('');
  $('#quadro').scrollLeft = rolagem;

  var atencao = dados.cards.filter(precisaAtencao).length;
  $('#sub').textContent = dados.cards.length + ' conversas' +
    (atencao ? ' · ' + atencao + ' precisam de resposta' : '');
}
function esqueletoQuadro(){
  $('#quadro').innerHTML = [1,2,3,4].map(function(){
    return '<section class="col"><div class="colh">&nbsp;</div><div class="drop">' +
      '<div class="esq"></div><div class="esq"></div></div></section>'; }).join('');
}
function atualizarContadores(){
  var n = dados.cards.filter(precisaAtencao).length;
  document.title = (n ? '(' + n + ') ' : '') + 'Conversas';
  var b = $('#bolFila'); b.hidden = !n; b.textContent = n;
}

/* Eventos delegados: registrados uma vez, valem para todo card desenhado. */
var quadro = $('#quadro');
quadro.addEventListener('click', function(e){
  if(e.target.closest('[data-mais]')){ verTodasResolvidas = true; desenhar(true); return; }
  var c = e.target.closest('.card'); if(c) abrir(c.dataset.chat, c);
});
quadro.addEventListener('keydown', function(e){
  var c = e.target.closest('.card');
  if(c && (e.key === 'Enter' || e.key === ' ')){ e.preventDefault(); abrir(c.dataset.chat, c); }
});
quadro.addEventListener('dragstart', function(e){
  var c = e.target.closest('.card'); if(!c) return;
  arrastando = true; c.classList.add('dragging');
  e.dataTransfer.setData('text/plain', c.dataset.chat);
});
quadro.addEventListener('dragend', function(e){
  arrastando = false; var c = e.target.closest('.card'); if(c) c.classList.remove('dragging');
});
quadro.addEventListener('dragover', function(e){
  var z = e.target.closest('.drop'); if(!z) return; e.preventDefault(); z.classList.add('over');
});
quadro.addEventListener('dragleave', function(e){
  var z = e.target.closest('.drop'); if(z && !z.contains(e.relatedTarget)) z.classList.remove('over');
});
quadro.addEventListener('drop', function(e){
  var z = e.target.closest('.drop'); if(!z) return;
  e.preventDefault(); z.classList.remove('over');
  mover(e.dataTransfer.getData('text/plain'), z.dataset.estagio);
});

async function mover(chat, estagio, silencioso){
  var card = dados.cards.find(function(c){ return c.chat_id === chat; });
  if(!card || card.estagio === estagio) return;
  var anterior = card.estagio;
  card.estagio = estagio; desenhar(true);
  try {
    await api('mover', {chat_id:chat, estagio:estagio});
    if(!silencioso) aviso('Movida para ' + etapaRotulo(estagio) +
      '. Se o cliente escrever, ela volta para a etapa automática.');
  } catch(e){ card.estagio = anterior; desenhar(true); falhou(e, 'Não foi possível mover'); }
  carregar(true);
}

/* Carga do quadro. Uma por vez; em falha, espera cada vez mais e avisa uma vez so. */
var carregando = false, falhasSeguidas = 0, rapidoAte = 0;
async function carregar(forcar){
  if(arrastando || carregando) return;
  carregando = true;
  try {
    var j = await api('listar');
    preparar(j.cards || []);
    if(conhecidos){
      novos = {};
      j.cards.forEach(function(c){ if(!conhecidos[c.chat_id]) novos[c.chat_id] = 1; });
    }
    conhecidos = {}; j.cards.forEach(function(c){ conhecidos[c.chat_id] = 1; });
    dados = j;
    try { ls('crm_ultimo_listar', JSON.stringify(j)); } catch(e) {}
    if(j.usuario && !usuarioAtual) identificar(j.usuario, j.usuario);
    falhasSeguidas = 0; $('#offline').hidden = true;
    atualizarContadores();
    if(vista === 'kanban') desenhar(forcar);
    if(atual) pintar(false);
  } catch(e){
    falhasSeguidas++;
    if(falhasSeguidas === 1) falhou(e, 'Não foi possível atualizar');
  } finally { carregando = false; }
}
function intervaloKanban(){
  if(falhasSeguidas) return Math.min(45000 * Math.pow(2, falhasSeguidas), 300000);
  return Date.now() < rapidoAte ? 15000 : 45000;
}
function depoisDeAcao(){ rapidoAte = Date.now() + 120000; carregar(true); }
function cicloKanban(){
  if(ativo() && vista === 'kanban') carregar();
  setTimeout(cicloKanban, intervaloKanban());
}

/* ==================== gaveta ==================== */
var origemFoco = null;
function rascunhoChave(chat){ return 'crm_nota_' + chat; }
function abrir(chat, origem){
  atual = chat; origemFoco = origem || document.activeElement; pintar._conv = null;
  $('#drawer').classList.add('open'); $('#mask').classList.add('on');
  document.body.classList.add('travado');
  try { history.pushState({gaveta:1}, ''); } catch(e) {}
  pintar(true);
  setTimeout(function(){ $('#dfechar').focus(); }, 60);
}
function fechar(semHistorico){
  if(!atual) return;
  atual = null;
  $('#drawer').classList.remove('open'); $('#mask').classList.remove('on');
  document.body.classList.remove('travado');
  if(!semHistorico && history.state && history.state.gaveta){ try { history.back(); } catch(e) {} }
  if(origemFoco && document.body.contains(origemFoco)) origemFoco.focus();
}
window.addEventListener('popstate', function(){ if(atual) fechar(true); });
$('#dfechar').onclick = function(){ fechar(); };
$('#mask').onclick = function(){ fechar(); };
document.addEventListener('keydown', function(e){ if(e.key === 'Escape' && atual) fechar(); });

async function pintar(recarregar){
  var c = dados.cards.find(function(x){ return x.chat_id === atual; });
  if(!c){ fechar(); return; }
  $('#dfone').textContent = contatoTitulo(c);
  // Atualizacao automatica nao pode tirar o foco de quem esta digitando.
  if(!recarregar && $('#drawer').contains(document.activeElement) &&
     /^(TEXTAREA|INPUT|SELECT)$/.test(document.activeElement.tagName)) return;

  var conv = pintar._conv;
  if(recarregar || !conv){
    if(recarregar) $('#dbody').innerHTML = '<div class="esq"></div><div class="esq"></div><div class="esq"></div>';
    try { conv = await api('conversa', {chat_id:atual}); } catch(e){ conv = {mensagens:[], erro:texto(e)}; }
    if(c.chat_id !== atual) return;
  }
  pintar._conv = conv;
  var msgs = conv.mensagens || [];
  var tel = String(c.telefone || '').replace(/\D/g, '');
  var rascunho = ls(rascunhoChave(c.chat_id));
  var nota = rascunho != null ? rascunho : (c.notas || '');
  var opcoes = dados.estagios.map(function(e){
    return '<option value="' + esc(e.estagio) + '"' + (e.estagio === c.estagio ? ' selected' : '') + '>' +
      esc(etapaRotulo(e.estagio)) + '</option>'; }).join('');

  $('#dbody').innerHTML =
    '<div class="bloco">' +
      '<div class="contato-topo">' + avatarHtml(c, true) +
        '<div><strong>' + esc(contatoTitulo(c)) + '</strong>' +
        (contatoSub(c) ? '<span class="card-meta">' + esc(contatoSub(c)) + '</span>' : '') + '</div></div>' +
      '<div class="acoes">' +
        (c.pausado
          ? '<button class="b pri" id="btDevolver" type="button">Devolver ao bot</button>'
          : '<button class="b pri" id="btAssumir" type="button">Assumir conversa</button>') +
        (tel ? '<a class="b" href="https://wa.me/' + esc(tel) + '" target="_blank" rel="noopener">Responder no WhatsApp</a>' : '') +
        (c.estagio !== 'resolvido'
          ? '<button class="b" id="btResolver" type="button">Marcar como resolvida</button>' : '') +
      '</div>' +
      (c.pausado ? '<p class="dica" style="margin:8px 0 0">O bot está pausado nesta conversa: a equipe responde. ' +
                   'Ele volta sozinho depois de um tempo sem resposta da equipe.</p>' : '') +
    '</div>' +

    '<div class="bloco"><h3>Conversa</h3><div class="chat" id="chat">' +
      (conv.erro ? '<div class="vazio">Não foi possível carregar a conversa: ' + esc(conv.erro) + '</div>'
      : msgs.length ? msgs.map(function(m){
          var quem = m.origem === 'humano' ? 'Equipe' : m.origem === 'bot' ? 'Bot' : 'Cliente';
          return '<div class="bolha ' + esc(m.direcao) + (m.origem === 'humano' ? ' humano' : '') + '">' +
            esc(m.texto || (m.audio ? 'Áudio enviado' : 'Mídia')) +
            '<small>' + quem + ' · ' + esc(m.quando) + '</small></div>'; }).join('')
      : '<div class="vazio">Nenhuma mensagem registrada ainda</div>') +
      (msgs.length >= 60 ? '<p class="dica" style="margin:4px 0 0">Mostrando as 60 mensagens mais recentes.</p>' : '') +
    '</div></div>' +

    '<div class="bloco"><h3>Situação</h3>' +
      '<div class="item"><label for="selEtapa">Etapa</label><select class="campo" id="selEtapa">' + opcoes + '</select></div>' +
      '<div class="item"><span>Bot</span><b>' + (c.pausado ? '<span class="tag tag-risco">Pausado</span>'
                                                         : '<span class="tag tag-ok">Ativo</span>') + '</b></div>' +
      '<div class="item"><span>Responsável</span><b>' + esc(c.responsavel || 'Ninguém') + '</b></div>' +
      '<div class="item"><span>Treinamento</span><b>' + esc(c.treinamento || 'Não agendado') + '</b></div>' +
      '<div class="item"><span>Idioma</span><b>' + esc(IDIOMA[c.idioma] || c.idioma || '-') + '</b></div>' +
      '<div class="item"><span>Mensagens</span><b class="num">' + (c.total_entrada || 0) + ' recebidas · ' +
        (c.total_saida || 0) + ' enviadas</b></div>' +
      '<div class="item"><span>Último contato</span><b>' + esc(idadeLonga(c.minutos)) + '</b></div></div>' +

    '<div class="bloco"><h3><label for="nota">Nota interna</label></h3>' +
      '<p class="dica">Só a equipe vê. ' + (rascunho != null ? '<b>Rascunho não salvo.</b>' : '') + '</p>' +
      '<textarea id="nota">' + esc(nota) + '</textarea>' +
      '<div class="acoes" style="margin-top:8px"><button class="b" id="btNota" type="button">Salvar nota</button></div></div>' +

    '<div class="bloco"><h3>Contato</h3>' +
      '<div class="item"><span>Nome no WhatsApp</span><b>' + esc(c.nome_whatsapp || '-') + '</b></div>' +
      (c.nome && c.nome !== c.nome_whatsapp
        ? '<div class="item"><span>Nome na equipe</span><b>' + esc(c.nome) + '</b></div>' : '') +
      '<div class="item"><span>Telefone</span><b>' + (tel
        ? esc(foneFmt(tel)) + '<button class="copiar" id="btCopiar" type="button" data-v="+' + esc(tel) + '">Copiar</button>'
        : 'Ainda não informado') + '</b></div>' +
      (!tel && idWhats(c) ? '<div class="item"><span>ID do WhatsApp</span><b>' + esc(idWhats(c)) +
        '<button class="copiar" id="btCopiar" type="button" data-v="' + esc(idWhats(c)) + '">Copiar</button></b></div>' : '') +
      (!tel ? '<p class="dica" style="margin:8px 0 0">O WhatsApp esconde o número de alguns contatos. Ele aparece aqui ' +
              'quando o WhatsApp informar, normalmente na próxima mensagem do cliente.</p>' : '') +
    '</div>';

  var chat = $('#chat'); if(chat) chat.scrollTop = chat.scrollHeight;
  var chave = rascunhoChave(c.chat_id);
  $('#nota').addEventListener('input', function(){ ls(chave, this.value); });
  $('#btNota').onclick = function(){
    var btn = this;
    ocupado(btn, 'Salvando...', async function(){
      try { await api('nota', {chat_id:c.chat_id, notas:$('#nota').value});
            ls(chave, null); aviso('Nota salva'); depoisDeAcao(); }
      catch(e){ falhou(e, 'Não foi possível salvar a nota'); }
    });
  };
  $('#selEtapa').onchange = function(){ mover(c.chat_id, this.value); };
  var bc = $('#btCopiar');
  if(bc) bc.onclick = async function(){
    try { await navigator.clipboard.writeText(bc.dataset.v); aviso('Copiado'); }
    catch(e){ aviso(bc.dataset.v); } };
  var ba = $('#btAssumir');
  if(ba) ba.onclick = function(){ ocupado(ba, 'Assumindo...', async function(){
    try { aviso((await api('assumir', {chat_id:c.chat_id})).aviso || 'Conversa assumida. O bot está pausado.');
          depoisDeAcao(); }
    catch(e){ falhou(e, 'Não foi possível assumir'); } }); };
  var bd = $('#btDevolver');
  if(bd) bd.onclick = function(){ ocupado(bd, 'Devolvendo...', async function(){
    try { aviso((await api('devolver', {chat_id:c.chat_id})).aviso || 'Conversa devolvida ao bot.');
          depoisDeAcao(); }
    catch(e){ falhou(e, 'Não foi possível devolver'); } }); };
  var br = $('#btResolver');
  if(br) br.onclick = function(){ ocupado(br, 'Resolvendo...', async function(){
    var anterior = c.estagio, chatId = c.chat_id;
    try {
      await api('resolver', {chat_id:chatId});
      fechar();
      aviso('Conversa marcada como resolvida', {rotulo:'Desfazer', fn:function(){ mover(chatId, anterior, true)
        .then(function(){ aviso('Desfeito'); }); }});
      depoisDeAcao();
    } catch(e){ falhou(e, 'Não foi possível resolver'); } }); };
}

/* ==================== dashboard ==================== */
function num(v){ return v == null ? '-' : String(v); }
function kpi(rot, valor, pe, classe){
  return '<div class="bloco kpi' + (classe ? ' ' + classe : '') + '"><div class="rot">' + esc(rot) + '</div>' +
         '<div class="valor">' + esc(num(valor)) + '</div>' +
         '<div class="pe">' + esc(pe || '') + '</div></div>';
}
function barrasV(lista, cada){
  if(!lista || !lista.length) return '<div class="vazio">Nenhum dado nos dias escolhidos</div>';
  var max = Math.max.apply(null, lista.map(function(d){ return d.qtd; }).concat([1]));
  return '<div class="gr" role="img" aria-label="Gráfico de barras">' + lista.map(function(d, i){
    var h = Math.round(d.qtd / max * 100);
    var mostra = i % cada === 0;
    return '<div class="br" title="' + esc(d.rotulo) + ': ' + d.qtd + '">' +
             '<span class="bn">' + (d.qtd && (lista.length <= 16 || mostra) ? d.qtd : '') + '</span>' +
             '<div class="bv" style="height:' + h + '%"></div>' +
             '<span class="bl">' + (mostra ? esc(d.rotulo) : '') + '</span></div>';
  }).join('') + '</div><div class="eixo"></div>';
}
function barrasH(lista, usarCor){
  if(!lista || !lista.length) return '<div class="vazio">Nenhum dado nos dias escolhidos</div>';
  var max = Math.max.apply(null, lista.map(function(d){ return d.qtd; }).concat([1]));
  return lista.map(function(d){
    var w = Math.round(d.qtd / max * 100);
    var cor = usarCor && d.cor ? ';background:' + esc(d.cor) : '';
    var rot = d.estagio ? etapaRotulo(d.estagio) : d.rotulo;
    return '<div class="bh"><span class="bhr">' + esc(rot) + '</span>' +
           '<span class="bht"><i style="width:' + w + '%' + cor + '"></i></span>' +
           '<span class="bhv">' + d.qtd + '</span></div>';
  }).join('');
}
function acoesDash(){
  $('#acoesTopo').innerHTML =
    '<label class="sr-only" for="perDias">Período</label>' +
    '<select class="campo" id="perDias">' +
      '<option value="7">Últimos 7 dias</option><option value="14" selected>Últimos 14 dias</option>' +
      '<option value="30">Últimos 30 dias</option><option value="90">Últimos 90 dias</option></select>';
  $('#perDias').onchange = function(){ carregarDash(); };
}
async function carregarDash(forcar){
  var alvo = $('#v-dashboard'), dias = Number(($('#perDias') || {}).value || 14);
  if(!cache['dash' + dias] || forcar) estado(alvo, 'carregando', 'Carregando indicadores...');
  var dash;
  try { dash = await comCache('dash' + dias, function(){ return api('dashboard', {dias:dias}); }, forcar); }
  catch(e){ if(e.message !== 'sessao') estado(alvo, 'erro', 'Não foi possível carregar o dashboard',
              texto(e), function(){ carregarDash(true); }); return; }
  if(vista !== 'dashboard') return;
  var k = dash.kpis || {};
  $('#sub').textContent = 'Últimos ' + dash.dias + ' dias · atualizado ' + (dash.gerado_em || '');
  alvo.innerHTML =
    '<div class="grade g4" style="margin-bottom:12px">' +
      kpi('Conversas no período', k.conversas, (k.novas || 0) + ' novas') +
      kpi('Resolvidas sem atendente', k.autonomia == null ? '-' : k.autonomia + '%',
          (k.com_humano || 0) + ' precisaram de atendente', 'bom') +
      kpi('Tempo médio de resposta do bot', k.resposta_seg == null ? '-' : k.resposta_seg + 's',
          (k.recebidas || 0) + ' recebidas · ' + (k.enviadas || 0) + ' enviadas') +
      kpi('Treinamentos à frente', k.futuros, (k.marcados || 0) + ' marcados · ' + (k.cancelados || 0) + ' cancelados') +
      kpi('Aguardando atendente', k.fila_agora, 'agora', k.fila_agora ? 'atencao' : '') +
      kpi('Bot pausado', k.pausados_agora, 'conversas com a equipe agora') +
    '</div>' +
    '<div class="grade g2">' +
      '<div class="bloco"><h3>Mensagens recebidas por dia</h3><p class="dica">Volume de entrada</p>' +
        barrasV(dash.por_dia, Math.max(1, Math.ceil((dash.por_dia || []).length / 7))) + '</div>' +
      '<div class="bloco"><h3>Movimento por hora do dia</h3><p class="dica">Bom para decidir quando reforçar a equipe</p>' +
        barrasV(dash.por_hora, 3) + '</div>' +
      '<div class="bloco"><h3>Conversas por etapa</h3><p class="dica">Como está o funil agora</p>' +
        barrasH(dash.estagios, true) + '</div>' +
      '<div class="bloco"><h3>Assuntos mais pedidos</h3><p class="dica">A partir dos áudios enviados</p>' +
        barrasH(dash.temas, false) +
        '<h3 style="margin-top:16px">Idioma dos clientes</h3><p class="dica">Detecção automática</p>' +
        barrasH((dash.idiomas || []).map(function(d){ return {rotulo:IDIOMA[d.rotulo] || d.rotulo, qtd:d.qtd}; }), false) +
      '</div></div>';
}

/* ==================== agenda ==================== */
var MES = ['janeiro','fevereiro','março','abril','maio','junho','julho','agosto',
           'setembro','outubro','novembro','dezembro'];
var mesCal = new Date(), rel = null;
function pdata(s){
  var m = /^(\d{2})\/(\d{2})\/(\d{4}) (\d{2}):(\d{2})/.exec(s || '');
  return m ? new Date(+m[3], +m[2]-1, +m[1], +m[4], +m[5]) : null;
}
async function carregarAgenda(forcar){
  var alvo = $('#v-agenda');
  if(!cache.agenda || forcar) estado(alvo, 'carregando', 'Carregando agenda...');
  try { rel = await comCache('agenda', function(){ return api('relatorio', {tipo:'treinamentos', dias:365}); }, forcar); }
  catch(e){ if(e.message !== 'sessao') estado(alvo, 'erro', 'Não foi possível carregar a agenda',
              texto(e), function(){ carregarAgenda(true); }); return; }
  if(vista === 'agenda') desenharAgenda();
}
function desenharAgenda(){
  if(!rel) return;
  var evs = (rel.linhas || []).map(function(l){
    return {quando:pdata(l[0]), texto:l[0], fone:l[1], situacao:l[2]};
  }).filter(function(e){ return e.quando && e.situacao === 'confirmado'; });

  var ano = mesCal.getFullYear(), mes = mesCal.getMonth();
  var prim = new Date(ano, mes, 1), ini = new Date(prim);
  ini.setDate(1 - prim.getDay());
  var hoje = new Date(); hoje.setHours(0,0,0,0);

  var celulas = '';
  for(var i = 0; i < 42; i++){
    var d = new Date(ini); d.setDate(ini.getDate() + i);
    var doDia = evs.filter(function(e){
      return e.quando.getFullYear() === d.getFullYear() && e.quando.getMonth() === d.getMonth() &&
             e.quando.getDate() === d.getDate(); });
    celulas += '<div class="celula' + (d.getMonth() !== mes ? ' fora' : '') +
      (d.getTime() === hoje.getTime() ? ' hoje' : '') + '">' +
      '<span class="dn">' + d.getDate() + '</span>' +
      doDia.map(function(e){
        var curto = e.fone.indexOf(' · ') > 0 ? e.fone.split(' · ')[0].split(' ')[0]
                  : (e.fone.replace(/\D/g, '').slice(-4) || e.fone);
        return '<span class="ev" title="' + esc(e.texto + ' · ' + e.fone) + '">' +
               esc(e.texto.slice(11,16)) + ' ' + esc(curto) + '</span>'; }).join('') +
      (doDia.length ? '<span class="ev-n">' + doDia.length + ' trein.</span>' : '') +
      '</div>';
  }
  var futuros = evs.filter(function(e){ return e.quando >= new Date(); })
                   .sort(function(a,b){ return a.quando - b.quando; });
  $('#sub').textContent = futuros.length + ' treinamentos confirmados à frente';

  $('#v-agenda').innerHTML =
    '<div class="bloco"><h3>Próximos treinamentos</h3>' +
      '<p class="dica">Confirmados, do mais próximo ao mais distante</p>' +
      (futuros.length ? '<div class="rol"><table><thead><tr><th>Quando</th><th>Contato</th></tr></thead><tbody>' +
        futuros.map(function(e){ return '<tr><td class="num">' + esc(e.texto) + '</td><td>' +
          esc(e.fone) + '</td></tr>'; }).join('') + '</tbody></table></div>'
        : '<div class="vazio">Nenhum treinamento marcado à frente</div>') + '</div>' +
    '<div class="bloco">' +
      '<div class="cal-topo"><h3>' + MES[mes] + ' de ' + ano + '</h3><span class="cresce"></span>' +
        '<button class="b mini" id="mAnt" type="button">Anterior</button>' +
        '<button class="b mini" id="mHoje" type="button">Hoje</button>' +
        '<button class="b mini" id="mProx" type="button">Próximo</button></div>' +
      '<div class="cal">' + ['dom','seg','ter','qua','qui','sex','sáb'].map(function(d){
        return '<div class="cald">' + d + '</div>'; }).join('') + celulas + '</div></div>';

  $('#mAnt').onclick  = function(){ mesCal = new Date(ano, mes-1, 1); desenharAgenda(); };
  $('#mProx').onclick = function(){ mesCal = new Date(ano, mes+1, 1); desenharAgenda(); };
  $('#mHoje').onclick = function(){ mesCal = new Date(); desenharAgenda(); };
}

/* ==================== relatorios ==================== */
var TIPOS_REL = {conversas:'Conversas', mensagens:'Mensagens', treinamentos:'Treinamentos'};
function desenharRelatorios(){
  $('#sub').textContent = 'Exporte os dados para planilha';
  $('#v-relatorios').innerHTML =
    '<div class="bloco"><h3>Gerar relatório</h3><p class="dica">Os dados saem em CSV e abrem direto no Excel</p>' +
      '<div class="acoes">' +
        '<label class="sr-only" for="relTipo">Tipo de relatório</label>' +
        '<select class="campo" id="relTipo">' + Object.keys(TIPOS_REL).map(function(k){
          return '<option value="' + k + '">' + TIPOS_REL[k] + '</option>'; }).join('') + '</select>' +
        '<label class="sr-only" for="relDias">Período</label>' +
        '<select class="campo" id="relDias">' +
          '<option value="7">Últimos 7 dias</option><option value="30" selected>Últimos 30 dias</option>' +
          '<option value="90">Últimos 90 dias</option><option value="365">Último ano</option></select>' +
        '<button class="b pri" id="relVer" type="button">Ver</button>' +
        '<button class="b" id="relCsv" type="button">Baixar CSV</button>' +
      '</div></div>' +
    '<div id="relSaida"></div>';
  $('#relVer').onclick = function(){ var b = this; ocupado(b, 'Carregando...', verRelatorio); };
  $('#relCsv').onclick = function(){ var b = this; ocupado(b, 'Gerando...', baixarCsv); };
}
function pegarRel(){
  var tipo = $('#relTipo').value, dias = Number($('#relDias').value);
  return comCache('rel-' + tipo + '-' + dias, function(){ return api('relatorio', {tipo:tipo, dias:dias}); });
}
async function verRelatorio(){
  var j;
  try { j = await pegarRel(); } catch(e){ falhou(e, 'Não foi possível gerar o relatório'); return; }
  var linhas = j.linhas || [];
  $('#relSaida').innerHTML = '<div class="bloco"><h3>' + esc(TIPOS_REL[j.tipo] || j.tipo) + '</h3>' +
    '<p class="dica">' + linhas.length + ' registros nos últimos ' + j.dias + ' dias</p>' +
    (linhas.length ? '<div class="rol"><table><thead><tr>' +
      j.colunas.map(function(c){ return '<th>' + esc(c) + '</th>'; }).join('') + '</tr></thead><tbody>' +
      linhas.slice(0,200).map(function(l){ return '<tr>' +
        l.map(function(v){ return '<td>' + esc(v) + '</td>'; }).join('') + '</tr>'; }).join('') +
      '</tbody></table></div>' + (linhas.length > 200 ? '<p class="dica" style="margin-top:8px">Mostrando os 200 primeiros. O CSV traz tudo.</p>' : '')
      : '<div class="vazio">Nenhum registro no período</div>') + '</div>';
}
async function baixarCsv(){
  var j;
  try { j = await pegarRel(); } catch(e){ falhou(e, 'Não foi possível gerar o relatório'); return; }
  // Celula que comeca com = + - @ vira formula no Excel: prefixa com apostrofo.
  var esq = function(v){ var s = String(v == null ? '' : v);
    if(/^[=+\-@\t\r]/.test(s)) s = "'" + s;
    return /[";\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
  var csv = [j.colunas.map(esq).join(';')]
    .concat((j.linhas || []).map(function(l){ return l.map(esq).join(';'); })).join('\r\n');
  var a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob(['﻿' + csv], {type:'text/csv;charset=utf-8'}));
  a.download = 'conversas-' + j.tipo + '-' + j.dias + 'dias.csv';
  document.body.appendChild(a); a.click(); a.remove();
  aviso('CSV gerado');
}

/* ==================== conexao do whatsapp ====================
   Esta tela nunca fica em branco e nunca apaga o QR enquanto o usuario
   aponta a camera: a atualizacao automatica so troca o que mudou. */
var ultConexao = null, timerConexao = null;
function conexaoDesenhar(c, erro, carregandoPrimeira){
  var ponto, titulo, txt, miolo = '';
  if(carregandoPrimeira){ ponto = 'acao'; titulo = 'Consultando o WhatsApp...'; txt = 'Isso leva alguns segundos.'; }
  else if(erro){ ponto = 'risco'; titulo = 'Não foi possível consultar'; txt = erro; }
  else if(c.conectado){
    ponto = 'ok'; titulo = 'WhatsApp conectado'; txt = 'O agente está recebendo e respondendo mensagens.';
    miolo = '<div style="align-self:stretch">' +
      '<div class="item"><span>Número</span><b class="num">' + esc(foneFmt((c.numero || '').split('@')[0]) || '-') + '</b></div>' +
      '<div class="item"><span>Perfil</span><b>' + esc(c.perfil || '-') + '</b></div></div>';
  }
  else if(c.qr){
    ponto = 'acao'; titulo = 'Escaneie o QR code'; txt = 'O agente conecta assim que você ler o código.';
    miolo =
      '<ol style="margin:0;padding-left:20px;color:var(--ink2);font-size:13px;line-height:1.9">' +
        '<li>Abra o WhatsApp no celular</li><li>Toque em <b>Aparelhos conectados</b></li>' +
        '<li>Toque em <b>Conectar aparelho</b></li><li>Aponte a câmera para o código abaixo</li></ol>' +
      '<div style="background:#fff;padding:16px;border-radius:var(--r-md);box-shadow:var(--sombra-1)">' +
        '<img id="qrImg" src="' + esc(c.qr) + '" alt="QR code para conectar o WhatsApp" ' +
        'style="width:260px;height:260px;display:block"></div>' +
      '<p class="dica" style="margin:0">O código se renova sozinho a cada 20 segundos.</p>';
  }
  else { ponto = 'alerta'; titulo = esc(c.rotulo || 'WhatsApp desconectado');
         txt = 'Aguardando o WhatsApp gerar um código. Isso leva alguns segundos.'; }

  var podeDesconectar = !!(c && c.conectado);
  $('#sub').textContent = carregandoPrimeira ? '' : (erro ? 'Erro na consulta' : (c.rotulo || ''));
  $('#v-conexao').innerHTML =
    '<div class="bloco estado" style="max-width:560px">' +
      '<div class="titulo-estado"><span class="ponto ' + ponto + '" aria-hidden="true"></span><h3>' + titulo + '</h3></div>' +
      '<p>' + esc(txt) + '</p>' + miolo +
      '<div class="acoes">' +
        '<button class="b" id="cnAtualizar" type="button">Atualizar</button>' +
        (podeDesconectar ? '<button class="b perigo" id="cnSair" type="button">Desconectar WhatsApp</button>' : '') +
      '</div>' +
      (podeDesconectar ? '<p class="dica" style="margin:0">Desconectar tira o agente do ar até alguém escanear o QR de novo. ' +
                         'Tenha o celular em mãos.</p>' : '') +
    '</div>';
  $('#cnAtualizar').onclick = function(){ carregarConexao(true); };
  var bs = $('#cnSair');
  if(bs) bs.onclick = function(){
    if(!confirm('Desconectar o WhatsApp?\n\nO agente para de responder até alguém escanear o QR de novo.')) return;
    ocupado(bs, 'Desconectando...', async function(){
      try { await conexao('desconectar'); aviso('Desconectado. O QR aparece em instantes.'); }
      catch(e){ falhou(e, 'Não foi possível desconectar'); }
      setTimeout(function(){ carregarConexao(true); }, 2500);
    });
  };
}
async function carregarConexao(primeira){
  if(primeira || !ultConexao) conexaoDesenhar(null, null, true);
  try {
    var c = await conexao('conexao');
    // Sessao parada nao gera QR sozinha: religa uma vez (guarda de 30s contra loop).
    if(c.parado && (Date.now() - (carregarConexao._religou || 0) > 30000)){
      carregarConexao._religou = Date.now();
      aviso('Religando a sessão para gerar o QR...');
      try { await conexao('iniciar'); } catch(e){ if(e.message === 'sessao') return; }
      await new Promise(function(r){ setTimeout(r, 7000); });
      try { c = await conexao('conexao'); } catch(e){ if(e.message === 'sessao') return; }
    }
    if(vista !== 'conexao') return;
    // Mesmo estado e mesmo QR: nao redesenha (nao pisca na frente da camera).
    var mudou = !ultConexao || JSON.stringify(ultConexao) !== JSON.stringify(c);
    ultConexao = c;
    if(mudou || primeira) conexaoDesenhar(c, null, false);
  }
  catch(e){ if(e.message !== 'sessao' && vista === 'conexao'){ ultConexao = null; conexaoDesenhar(null, texto(e), false); } }
  agendarConexao();
}
/* Ritmo: 20s enquanto ha QR na tela (ele expira), 2 min quando ja conectado. */
function agendarConexao(){
  clearTimeout(timerConexao);
  if(vista !== 'conexao') return;
  var ms = ultConexao && ultConexao.conectado ? 120000 : 20000;
  timerConexao = setTimeout(function(){ if(ativo() && vista === 'conexao') carregarConexao(); else agendarConexao(); }, ms);
}

/* ==================== equipe e conta ==================== */
async function carregarEquipe(){
  var alvo = $('#v-equipe');
  estado(alvo, 'carregando', 'Carregando equipe...');
  var equipe;
  try { equipe = await api('equipe'); }
  catch(e){ if(e.message !== 'sessao') estado(alvo, 'erro', 'Não foi possível carregar a equipe',
              texto(e), carregarEquipe); return; }
  if(vista !== 'equipe') return;
  var us = equipe.usuarios || [];
  $('#sub').textContent = us.length + (us.length === 1 ? ' pessoa com acesso' : ' pessoas com acesso');
  alvo.innerHTML =
    '<div class="bloco"><h3>Quem tem acesso</h3>' +
      '<p class="dica">As senhas ficam protegidas (hash): ninguém consegue lê-las.</p>' +
      '<div class="rol"><table><thead><tr><th>Usuário</th><th>Nome</th><th>Último acesso</th></tr></thead><tbody>' +
      us.map(function(u){ return '<tr><td>' + esc(u.usuario) + (u.usuario === usuarioAtual ? ' <span class="tag tag-acao">você</span>' : '') +
        '</td><td>' + esc(u.nome) + '</td><td class="num">' + esc(u.ultimo_acesso || 'Nunca entrou') + '</td></tr>'; }).join('') +
      '</tbody></table></div></div>' +
    '<div class="grade g2" style="margin-top:12px">' +
      '<div class="bloco"><h3>Adicionar pessoa</h3><p class="dica">Senha com 8 caracteres ou mais</p>' +
        '<div class="form">' +
          '<div><label for="nvUser">Usuário</label><input id="nvUser" autocomplete="off" autocapitalize="none" spellcheck="false"></div>' +
          '<div><label for="nvNome">Nome</label><input id="nvNome" autocomplete="off"></div>' +
          '<div><label for="nvSenha">Senha</label><input id="nvSenha" type="password" autocomplete="new-password"></div>' +
          '<div><button class="b pri" id="nvCriar" type="button">Adicionar pessoa</button></div>' +
        '</div></div>' +
      '<div class="bloco"><h3>Minha conta</h3><p class="dica">Ao trocar a senha, você precisa entrar de novo.</p>' +
        '<div class="form">' +
          '<div><label for="snAtual">Senha atual</label><input id="snAtual" type="password" autocomplete="current-password"></div>' +
          '<div><label for="snNova">Nova senha</label><input id="snNova" type="password" autocomplete="new-password"></div>' +
          '<div class="acoes"><button class="b pri" id="snTrocar" type="button">Trocar senha</button>' +
            '<button class="b" id="snTema" type="button">Alternar tema</button>' +
            '<button class="b" id="snSair" type="button">Sair da conta</button></div>' +
        '</div></div>' +
    '</div>';
  $('#nvCriar').onclick = function(){ var b = this; ocupado(b, 'Adicionando...', async function(){
    try {
      await api('criar_usuario', {usuario:$('#nvUser').value.trim(),
                                  nome:$('#nvNome').value.trim(), senha:$('#nvSenha').value});
      aviso('Acesso criado'); carregarEquipe();
    } catch(e){ falhou(e, 'Não foi possível adicionar'); } }); };
  $('#snTrocar').onclick = function(){ var b = this; ocupado(b, 'Trocando...', async function(){
    var nova = $('#snNova').value;
    if(nova.length < 8){ aviso(ERROS.SENHA_CURTA); return; }
    try {
      await api('trocar_senha', {atual:$('#snAtual').value, nova:nova});
      guardar(''); mostrarAcesso('Senha alterada. Entre com a nova senha.');
    } catch(e){ falhou(e, 'Não foi possível trocar a senha'); } }); };
  $('#snTema').onclick = alternarTema;
  $('#snSair').onclick = sair;
}

/* ==================== inicio ==================== */
function ativo(){ return token && !$('#app').hidden && document.visibilityState !== 'hidden'; }
window.addEventListener('online',  function(){ $('#offline').hidden = true; if(ativo()) carregar(true); });
window.addEventListener('offline', function(){ $('#offline').hidden = false; });
document.addEventListener('visibilitychange', function(){
  if(!ativo()) return;
  if(vista === 'kanban')  carregar();
  if(vista === 'conexao') carregarConexao();
});

// O ciclo roda sempre; so faz algo com sessao ativa (ativo()), inclusive
// para quem entra pela tela de login depois.
setTimeout(cicloKanban, intervaloKanban());

(async function(){
  if(!token){ mostrarAcesso(); return; }
  $('#app').hidden = false;
  navegar('kanban');
  // Desenha na hora com o ultimo quadro conhecido e atualiza quando a resposta chegar.
  var salvo = null;
  try { salvo = JSON.parse(ls('crm_ultimo_listar') || 'null'); } catch(e) {}
  if(salvo && salvo.cards){ preparar(salvo.cards); dados = salvo; atualizarContadores(); desenhar(true); }
  else esqueletoQuadro();
  try {
    var j = await api('listar');
    preparar(j.cards || []); dados = j;
    conhecidos = {}; j.cards.forEach(function(c){ conhecidos[c.chat_id] = 1; });
    ls('crm_ultimo_listar', JSON.stringify(j));
    identificar(j.usuario, j.usuario); atualizarContadores(); desenhar(true);
  } catch(e){
    // Erro de rede nao e senha errada: mostra o erro e deixa tentar de novo.
    if(e.message !== 'sessao' && !(salvo && salvo.cards))
      estado($('#quadro'), 'erro', 'Não foi possível carregar as conversas', texto(e), function(){ location.reload(); });
    else if(e.message !== 'sessao') falhou(e, 'Mostrando dados salvos. Não foi possível atualizar');
  }
})();

})();
