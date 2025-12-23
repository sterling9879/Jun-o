# Video Reverser

Sistema de automação para concatenar vídeos numerados sequencialmente em **ordem INVERSA** usando FFMPEG.

## Visão Geral

Este projeto detecta automaticamente vídeos numerados (001.mp4, 002.mp4, 003.mp4...) em uma pasta e os concatena em ordem reversa, gerando um único arquivo de vídeo final.

## Estrutura do Projeto

```
/video-reverser/
├── input/              # Pasta onde os vídeos serão colocados
├── output/             # Pasta para o vídeo final
├── install.sh          # Script de instalação para VPS
├── process.sh          # Script principal de processamento (CLI)
├── README.md           # Esta documentação
└── web/                # Interface Web
    ├── app.py          # Backend Flask
    ├── install.sh      # Instalação da interface web
    ├── start.sh        # Iniciar servidor web
    ├── requirements.txt
    ├── templates/
    │   └── index.html
    └── static/
        ├── css/
        │   └── style.css
        └── js/
            └── app.js
```

## Instalação

### Requisitos

- Sistema operacional: Ubuntu, Debian, CentOS, Fedora ou RHEL
- Privilégios de root/sudo (para instalação do FFMPEG)
- Espaço em disco: mínimo 2x o tamanho total dos vídeos de entrada

### Instalação Rápida

```bash
# Clonar ou copiar os arquivos para o servidor

# Dar permissão de execução e instalar
chmod +x install.sh
./install.sh
```

O script de instalação irá:
- Detectar seu sistema operacional
- Instalar o FFMPEG (se não estiver instalado)
- Criar a estrutura de pastas
- Configurar permissões
- Validar a instalação

## Uso

### Uso Básico

```bash
# 1. Coloque seus vídeos na pasta input/
cp /caminho/dos/videos/*.mp4 input/

# 2. Execute o processamento
./process.sh
```

### Opções Disponíveis

| Opção | Descrição |
|-------|-----------|
| `--output-name NAME` | Define nome customizado para o arquivo de saída (padrão: final.mp4) |
| `--clean` | Remove os vídeos da pasta input/ após processamento bem-sucedido |
| `--force` | Ignora gaps na sequência numérica e processa mesmo assim |
| `--reencode` | Re-encoda os vídeos (mais lento, mas garante compatibilidade) |
| `--verbose` | Mostra informações detalhadas durante o processamento |
| `--help` | Exibe ajuda |

### Exemplos

```bash
# Processamento básico (detecta automaticamente)
./process.sh

# Com nome de saída customizado
./process.sh --output-name meu_video_reverso.mp4

# Limpar input após processamento
./process.sh --clean

# Forçar processamento mesmo com gaps na numeração
./process.sh --force

# Re-encodar vídeos com specs diferentes
./process.sh --reencode

# Combinar várias opções
./process.sh --output-name compilacao.mp4 --clean --verbose
```

## Formatos de Vídeo Suportados

- `.mp4`
- `.mov`
- `.avi`
- `.mkv`
- `.webm`
- `.m4v`
- `.wmv`
- `.flv`

## Padrões de Numeração

O sistema detecta automaticamente o padrão de numeração:

- 3 dígitos: `001.mp4`, `002.mp4`, ..., `999.mp4`
- 4 dígitos: `0001.mp4`, `0002.mp4`, ..., `9999.mp4`
- Outros padrões numéricos são suportados

## Output Esperado

```
╔═══════════════════════════════════════════════════════════════╗
║                    === Video Reverser ===                     ║
╚═══════════════════════════════════════════════════════════════╝

[INFO] Escaneando pasta input/...
Encontrados: 60 vídeos (001.mp4 ate 060.mp4)
Sequencia: completa ✓

[INFO] Gerando ordem inversa...
060.mp4 → 059.mp4 → 058.mp4 → ... → 002.mp4 → 001.mp4

[INFO] Concatenando com FFMPEG...
[██████████████████████████████████████████████████] 100%

╔═══════════════════════════════════════════════════════════════╗
║                       ✓ Concluido!                            ║
╚═══════════════════════════════════════════════════════════════╝

  - Videos processados:     60
  - Arquivo final:          /video-reverser/output/final.mp4
  - Tamanho:                2.4 GB
  - Duracao:                01:32:45
  - Tempo de processamento: 45s
```

## Validação de Sequência

O sistema verifica automaticamente se a sequência está completa:

- ✓ **Sequência completa**: `001, 002, 003, 004, 005` → processa normalmente
- ⚠️ **Sequência com gaps**: `001, 002, 004, 005` (faltando 003) → pergunta se deseja continuar

Use `--force` para ignorar a validação de gaps.

## Métodos de Concatenação

### Stream Copy (Padrão)

```bash
./process.sh
```

- **Vantagem**: Muito rápido (sem re-encoding)
- **Requisito**: Vídeos devem ter mesmo codec/resolução
- **Uso**: Quando todos os vídeos têm as mesmas especificações

### Re-encode

```bash
./process.sh --reencode
```

- **Vantagem**: Garante compatibilidade entre vídeos diferentes
- **Desvantagem**: Mais lento, requer mais processamento
- **Uso**: Quando vídeos têm resoluções/codecs diferentes
- **Configuração**: H.264, CRF 23, AAC 192kbps

## Logs

Os logs são salvos em:
- `/var/log/video-reverser.log` (se tiver permissão)
- `./video-reverser.log` (fallback local)

## Requisitos de VPS

| Recurso | Mínimo | Recomendado |
|---------|--------|-------------|
| RAM | 2 GB | 4 GB |
| CPU | 1 core | 2+ cores |
| Storage | 2x tamanho dos vídeos | 3x tamanho dos vídeos |

## Solução de Problemas

### FFMPEG não encontrado

```bash
# Execute a instalação novamente
./install.sh
```

### Erro de permissão

```bash
# Verifique as permissões das pastas
chmod 755 input/ output/
chmod +x *.sh
```

### Vídeos com specs diferentes

```bash
# Use o modo re-encode
./process.sh --reencode
```

### Sequência incompleta

```bash
# Force o processamento
./process.sh --force
```

### Espaço em disco insuficiente

O sistema precisa de espaço livre equivalente a pelo menos 2x o tamanho total dos vídeos de entrada para garantir que o arquivo de saída possa ser criado.

## Notas Importantes

1. **Performance**: Para melhor velocidade, certifique-se de que todos os vídeos têm o mesmo codec e resolução
2. **Backup**: Sempre mantenha um backup dos vídeos originais antes de usar `--clean`
3. **Numeração**: Vídeos devem seguir padrão numérico no início do nome do arquivo
4. **Memória**: VPS com pouca RAM podem ter problemas com vídeos muito grandes no modo `--reencode`

## Interface Web

O Video Reverser também inclui uma interface web moderna para facilitar o uso.

### Instalação da Interface Web

```bash
# Após instalar o sistema base
cd web
chmod +x install.sh start.sh
./install.sh
```

### Iniciar o Servidor Web

```bash
cd web

# Modo desenvolvimento (padrão)
./start.sh

# Com porta customizada
./start.sh --port 8080

# Modo produção (com Gunicorn)
./start.sh --production
```

### Acessar a Interface

Abra o navegador em: `http://localhost:5000`

### Funcionalidades da Interface Web

- **Upload de vídeos**: Arraste e solte ou clique para selecionar
- **Visualização da fila**: Lista todos os vídeos com duração, tamanho e resolução
- **Validação de sequência**: Detecta automaticamente gaps na numeração
- **Opções de processamento**: Nome do output, re-encode, forçar processamento
- **Barra de progresso**: Acompanhe o processamento em tempo real
- **Download direto**: Baixe o vídeo processado pela interface
- **Histórico**: Lista de vídeos já processados

### Screenshots

A interface apresenta:
- Design moderno dark theme
- Cards organizados por função
- Estatísticas em tempo real
- Notificações toast para feedback
- Responsivo para mobile

## Licença

Este projeto é de uso livre. Use por sua conta e risco.
