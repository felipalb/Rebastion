# Rebastion

Roguelite de arena para iOS com visual pixel-art neon. Você controla um herói robótico que dispara automaticamente, ajusta a mira arrastando o dedo, sobrevive a ondas cada vez mais agressivas e monta uma build única combinando tiros elementais, fusões e mutações.

## O jogo

**Loop principal:** mirar → eliminar a onda → escolher uma mutação → enfrentar a próxima. A cada cinco ondas aparece um chefe.

- **Combate:** disparo automático com mira por arrasto. Combos aumentam o multiplicador de pontuação.
- **Heróis:** Vanguarda, Ricochete, Pyra e Glacius. Cada um tem um kit inicial próprio e é desbloqueado com núcleos.
- **Ultimates:** Pulso Nova, Estase, Tempestade e Revoada. A carga vem dos abates.
- **Tiros elementais e fusões:** ígneo, glacial, voltaico, tóxico, detonador, fantasma e vampírico, que se combinam em fusões como Núcleo de Plasma, Tempestade Glacial, Névoa Escaldante e Espectro Faminto.
- **Mutações passivas:** 13 passivas com raridades (comum, rara, lendária e fusão), níveis, ganhos fortes e contrapartidas.
- **Inimigos:** comum, corredor, tanque, divisor, atirador, blindado e bombardeiro, com padrões de projétil próprios (teleguiado, bifurcado, estilhaçante, explosivo em anel…).
- **Chefes:** Soberano do Vazio, Hidra Neon, Colosso Mecha e Serafim de Lâminas.
- **Modificadores de onda:** Invasão, Frenesi, Blindados e Enxame.
- **Evolução visual:** coroa, capa, pods, satélites, halo e núcleo evoluem o visual do herói ao longo da run, em quatro tiers de raridade.
- **Meta-progressão:** Laboratório com upgrades permanentes (Vitalidade, Potência, Reator Inicial, Sabedoria, Arsenal, Fortuna, Vantagem) comprados com os núcleos ganhos em cada run.
- **Game Center:** placares de pontuação e de onda, além de 17 conquistas.
- **Backend experimental:** servidor de placar e desafio diário (ainda não integrado ao app).

## Tecnologias

| Camada | Tecnologia |
| --- | --- |
| Linguagem | Swift |
| UI / menus / HUD | SwiftUI, Observation (`@Observable`) |
| Renderização do jogo | SpriteKit (`SKScene`, atlas e animações por frames) |
| Áudio | AVFoundation (`AVAudioEngine`, síntese procedural de efeitos) |
| Feedback tátil | UIKit (haptics) |
| Social | GameKit (Game Center: autenticação, leaderboards e conquistas) |
| Persistência | `Codable` + JSON em Application Support (perfil do jogador) |
| Aleatoriedade | Gerador com seed próprio (`SeededGenerator`) para runs determinísticas |
| Backend | Python 3, apenas biblioteca padrão (`http.server`), com persistência em JSON |
| Assets | Pixel-art no Asset Catalog do Xcode |

**Requisitos:** Xcode 26 ou mais recente, iOS 17.0+.

## Estrutura

```
Rebastion/
├── RunGame/                  # Projeto Xcode
│   ├── RunGame.xcodeproj
│   └── RunGame/
│       ├── Game/             # Motor do jogo, modelos, eventos e RNG com seed
│       ├── Scene/            # Cena SpriteKit, nós, texturas, animações e equipamento do herói
│       ├── UI/               # Telas SwiftUI: menu, HUD, upgrades, overlays e ajustes
│       ├── Meta/             # Perfil do jogador, laboratório, conquistas e Game Center
│       ├── Feedback/         # Som e haptics
│       └── Assets.xcassets   # Sprites, animações, projéteis e ícone
├── backend/
│   └── server.py             # API de placar e desafio diário
└── design/                   # Referências visuais
```

## Executar o app

1. Abra `RunGame/RunGame.xcodeproj` no Xcode.
2. Selecione seu time de desenvolvimento em *Signing & Capabilities* (o Game Center exige uma conta de desenvolvedor).
3. Escolha um iPhone ou simulador e execute o scheme `RunGame`.
4. O herói dispara sozinho. Arraste dentro da arena para mirar e mantenha o dedo parado por 0,8 s para ativar a Ultimate quando ela estiver carregada.

## Executar o backend (experimental)

Sem dependências externas:

```bash
python3 backend/server.py
```

O servidor sobe em `http://127.0.0.1:8000`.

| Método | Rota | Descrição |
| --- | --- | --- |
| `GET` | `/health` | Status do servidor |
| `GET` | `/daily` | Desafio diário |
| `GET` | `/leaderboard` | Placar |
| `POST` | `/scores` | Envia pontuação: `{ "player": "Runner", "score": 500, "wave": 4 }` |

O app ainda não consome esse servidor: hoje, os placares online passam pelo Game Center.

## Licença

Distribuído sob a licença descrita em [LICENSE](LICENSE).
