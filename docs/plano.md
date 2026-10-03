# Plano de implementação

## Visão

Jogo de sobrevivência e crescimento em mundo pós-apocalíptico, com a jogabilidade de um RTS
isométrico. Começa com uma família de 4 pessoas (esposa, esposo, 2 filhos) isolada no mato no
início do surto de zumbis e pode crescer até uma comunidade de cerca de 150 pessoas.
Não há vitória: o jogo termina quando a comunidade morre.

## Decisões fechadas

- **Motor**: Godot 4.7, GDScript, 2D isométrico, single-player, Windows (desenvolvimento também no macOS).
- **Combate**: as pessoas se defendem sozinhas; o jogador decide posicionamento, fortificações e fuga.
- **Necessidades**: fome e descanso por pessoa, mais moral da comunidade.
- **Mapa**: grande e fixo por partida (256x256) com névoa. Mundo infinito fica para reavaliar depois.
- **Conhecimento**: os atributos são da comunidade, derivados das habilidades dos indivíduos.
  Pode ser perdido com mortes e preservado por ensino e livros.
- **Ameaça**: poucos zumbis no começo; aumentam com o tempo e com a atividade da comunidade
  (barulho, fumaça, luz).
- **Crescimento**: por sobreviventes encontrados e por filhos nascidos na comunidade.

## Consequências da meta de 150 pessoas

- **Trabalho automático**: com 4 pessoas o jogador dá ordens diretas; com 150 isso é inviável.
  As pessoas precisam escolher tarefas sozinhas a partir de funções e prioridades definidas
  pelo jogador. Ordens diretas continuam existindo como exceção.
- **Orçamento de simulação**: 150 pessoas mais centenas de zumbis a 10 ticks/s em GDScript exige
  índice espacial para buscas de vizinhança, decisões de IA escalonadas (não todo tick) e limite
  de buscas de caminho por tick.
- **Zumbis baratos**: zumbis não usam A*; seguem um campo de atração (barulho/cheiro) com
  desvio local simples.
- **Renderização**: o terreno é desenhado em blocos (chunks) que o motor descarta quando estão
  fora da tela; passa a TileMapLayer quando houver arte de verdade. Entidades fora da tela não
  são desenhadas.
- **Interface de gestão**: lista de pessoas, painel da comunidade e alertas, em vez de depender
  de selecionar indivíduos no mapa.

## Etapas

Cada etapa termina com algo jogável e com testes da simulação em `tests/`.

Estado: etapas 0, 1, 2, 3, 4 e 5 implementadas. Próxima: etapa 6.

Pendências conhecidas das etapas feitas:
- A conferência visual é parcial: névoa, locais no mapa, painel de sobreviventes e textos do
  HUD foram vistos em capturas de tela; cliques e arrasto do mouse nunca foram exercitados
  (os testes rodam sem janela).
- Munição e remédios vêm do saque, que é finito, ou da oficina, que exige mecânica 3
  (munição) ou medicina 3 (remédios). Sem esse conhecimento não há fonte renovável: no teste
  de crescimento a comunidade chega a 20 pessoas com a munição zerada.
- A névoa só registra o que já foi explorado: zumbis e animais aparecem em qualquer área
  explorada, mesmo sem ninguém por perto.
- Uma expedição faz uma viagem por ordem e cada pessoa traz um único tipo de recurso.
- Recusar sobreviventes não tem custo; a consequência entra com a moral (etapa 6).
- Crianças que chegam com um grupo não têm vínculo de parentesco com os adultos dele.
- Fumaça não existe como fonte de atração; só barulho de trabalho, luz das casas à noite e tiros.
- O ensino é abstrato: basta quem sabe estar vivo, não precisa estar presente. Estuda-se ao
  lado de uma casa; não existe escola.
- Um livro interrompido (sono, ataque) recomeça do zero.
- Não há habilidade própria para lenha nem sucata: cortar madeira treina construção e
  recolher sucata treina mecânica.
- As taxas de prática e estudo não foram balanceadas; só há teste de que funcionam.
- Com os requisitos nos botões, o painel inferior do HUD cobre boa parte da tela. O texto
  da oficina selecionada não foi visto em captura de tela.
- Zumbis não calculam rota: contornam obstáculos por tentativa e podem ficar presos atrás de
  florestas e lagos grandes.
- `src/sim/game_state.gd` passou de 1800 linhas e deve ser dividido (pessoas, zumbis, trabalho).
  As regras das etapas 4 e 5 já ficam à parte, em `src/sim/exploration.gd` e
  `src/sim/knowledge.gd`, como funções estáticas sobre o estado; o mesmo formato serve para
  a divisão.
- Lenha ainda não é consumida; a madeira só tem meta de estoque. O consumo entra com as
  estações (etapa 6), quando houver consequência para a falta.
- As funções padrão de uma criança não mudam sozinhas quando ela vira adulta (etapa 6).

Testes, a partir da pasta do projeto:

    godot --headless --path . -s res://tests/sim_smoke.gd
    godot --headless --path . -s res://tests/load_test.gd

### Etapa 0 — Fundação para escala
- Mapa 256x256 com terreno em blocos e limites de câmera.
- Zumbi mínimo (vaga e persegue quem vê, sem combate) para o teste de carga ser realista.
- Índice espacial e fila de buscas de caminho com orçamento por tick.
- Teste de carga sem janela: 150 pessoas e 500 zumbis simulados, medindo o tempo por tick.
- Critério: o tick médio cabe com folga no orçamento a 5x de velocidade.

### Etapa 1 — A família
- `Pessoa` substitui o aldeão: nome, idade, parentesco, habilidades, fome, descanso, saúde.
- Recursos novos: comida, água, madeira, sucata, remédios, munição.
- Consumo diário por pessoa, ciclo de dia e noite, casa inicial com camas e estoque.
- Morte permanente e fim de jogo quando todos morrem.
- Critério: a família de 4 sobrevive ou morre de fome conforme as decisões do jogador.

### Etapa 2 — Trabalho automático
- Funções e prioridades por pessoa (coletar, caçar, plantar, construir, carregar, vigiar).
- Pessoas escolhem tarefas sozinhas, comem e dormem por conta própria.
- Produção sustentável: horta, caça, poço, lenha.
- Critério: a família se mantém por um ano de jogo sem ordens diretas.

### Etapa 3 — Zumbis e defesa
- Zumbis com atração por barulho, fumaça e luz; mais ativos à noite.
- Defesa automática, ferimentos e tratamento.
- Fortificações em degraus: cerca, paliçada, muro, torre de vigia, armadilhas.
- Ritmo de ameaça que cresce com os anos e com o tamanho da comunidade.
- Critério: uma base sem defesas cai; uma base fortificada resiste.

### Etapa 4 — Exploração e sobreviventes
- Névoa sobre o mapa e pontos de interesse com saque finito.
- Expedições: grupo enviado, risco proporcional à distância, base desprotegida.
- Sobreviventes encontrados ou que chegam; aceitar ou recusar.
- Mais casas e limite de moradia.
- Critério: a comunidade passa de 4 para cerca de 20 pessoas por exploração.

### Etapa 5 — Conhecimento
- Habilidades crescem com a prática; nível da comunidade derivado dos indivíduos.
- Conhecimento desbloqueia construções, receitas e melhorias (dados em `data/`).
- Ensino entre pessoas, livros encontrados ou escritos, perda de conhecimento por morte.
- Critério: perder o único especialista bloqueia algo que antes era possível.

### Etapa 6 — Longo prazo
- Estações do ano, moral da comunidade.
- Casais, nascimentos, crianças que crescem e aprendem com os adultos.
- Hordas migratórias e eventos.
- Interface de gestão para comunidades grandes.
- Balanceamento do arco família, abrigo, assentamento, comunidade, vila.
- Critério: uma partida chega a 150 pessoas com desempenho estável.

### Etapa 7 — Acabamento
- Arte e animações definitivas, som e música.
- Menu, opções, vários saves.
- Exportação para Windows.

## Em aberto

- Nome do jogo (o repositório se chama `baseapocalipse`; o projeto ainda se chama "Imperio").
