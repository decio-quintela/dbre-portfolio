# Anki Flashcards — Linux for DBA

Reference file for Anki cards. Import or create manually at apps.ankiweb.net

---

## Deck: Linux Processes

Q: Como ver qual processo PostgreSQL está usando mais CPU?
A: ps aux --sort=-%cpu | grep postgres | head -5

Q: O que significa STAT = R no output do ps?
A: Running — o processo está ativamente consumindo CPU agora.

Q: O que significa STAT = D no output do ps?
A: Waiting for disk I/O — processo bloqueado esperando o disco responder. Indica gargalo de I/O.

Q: Qual a diferença entre kill -2 e kill -15 no PostgreSQL?
A: kill -2 (SIGINT) cancela a query mantendo a conexão aberta.
   kill -15 (SIGTERM) encerra a conexão graciosamente com rollback.

Q: Por que nunca usar kill -9 no processo postmaster?
A: O SIGKILL mata imediatamente sem checkpoint. O PG entra em crash recovery na próxima inicialização, causando downtime desnecessário.

Q: Como identificar o PID do postmaster (processo pai)?
A: pgrep -x postgres | head -1
   É o processo pai de todos os outros — nunca o mate.

Q: Qual a alternativa mais segura ao kill para cancelar uma query?
A: SELECT pg_cancel_backend(PID); — pelo psql.
   Ou SELECT pg_terminate_backend(PID); para encerrar a conexão.

---

## Deck: Disk and I/O

Q: Qual comando mostra o uso de disco de todas as partições?
A: df -h
   Alerta se Use% > 80%. Crítico se > 90%.

Q: Como encontrar qual diretório do PostgreSQL está ocupando mais espaço?
A: du -sh /var/lib/postgresql/* | sort -rh | head -10

Q: O que significa %util > 80% no iostat?
A: O disco está saturado — não consegue atender todas as requisições de I/O.
   Investigar qual processo está gerando mais escrita com iotop.

Q: O que significa await > 20ms no iostat?
A: Alta latência de I/O — o disco está demorando para responder.
   Pode causar lentidão no PostgreSQL mesmo com índices corretos.

Q: Como instalar e usar o iostat no WSL?
A: sudo apt install sysstat -y
   iostat -x 2  (atualiza a cada 2 segundos)

Q: Qual comando mostra qual processo está gerando mais I/O de disco?
A: sudo iotop -o  (mostra só processos com I/O ativo)

Q: Onde o PostgreSQL armazena os WALs e como ver o tamanho?
A: /var/lib/postgresql/16/main/pg_wal/
   du -sh /var/lib/postgresql/16/main/pg_wal/

---

## Deck: Network

Q: Como verificar se o PostgreSQL está escutando na porta 5432?
A: ss -tulnp | grep 5432
   Se não aparecer nada, o PG não está rodando ou está em outra porta.

Q: Como contar quantas conexões TCP estão ativas na porta 5432?
A: ss -tnp | grep 5432 | wc -l

Q: Como testar se a API do Patroni está respondendo?
A: curl -s http://localhost:8008/health
   Retorna JSON com state, role e server_version.

Q: Como saber se um nó Patroni é o primary pelo curl?
A: curl -s -o /dev/null -w "%{http_code}" http://localhost:8008/master
   200 = é o primary. 503 = é réplica.

Q: Qual a diferença entre ss e netstat?
A: ss é moderno e mais rápido (parte do iproute2).
   netstat é legado mas ainda muito encontrado em servidores antigos.
   Em produção você vai usar os dois — saiba ambos.

---

## Deck: Logs and Text

Q: Como acompanhar o log do PostgreSQL ao vivo no Docker?
A: docker logs -f pg-lab
   Para instalação nativa: tail -f /var/log/postgresql/postgresql-*.log

Q: Como filtrar só erros no log do PostgreSQL?
A: grep "ERROR" postgresql.log
   Para monitorar ao vivo: docker logs -f pg-lab 2>&1 | grep -i "error\|fatal"

Q: Como contar quantos erros existem no log sem listá-los?
A: grep -c "ERROR" postgresql.log

Q: O que faz o awk '{print $2, $11}' no output do ps?
A: Imprime a 2ª coluna (PID) e a 11ª coluna (comando).
   $1=USER $2=PID $3=%CPU $4=%MEM ... $11=COMMAND

Q: Como buscar múltiplos termos no grep?
A: grep -i "deadlock\|lock timeout\|fatal" postgresql.log
   O \| funciona como OR. O -i ignora maiúsculas/minúsculas.

---

## Deck: Bash Scripting

Q: O que é o shebang e por que é necessário?
A: #!/bin/bash — primeira linha de todo script.
   Diz ao Linux qual interpretador usar para executar o arquivo.

Q: Como dar permissão de execução a um script Bash?
A: chmod +x nome-do-script.sh
   Depois executar: bash nome-do-script.sh ou ./nome-do-script.sh

Q: Como capturar o output de um comando em uma variável Bash?
A: RESULTADO=$(comando)
   Exemplo: CONNS=$(psql -t -c "SELECT count(*) FROM pg_stat_activity;")

Q: Como fazer uma condição no Bash para comparar números?
A: if [ $NUMERO -gt 80 ]; then
     echo "maior que 80"
   fi
   -gt=maior -lt=menor -eq=igual -ne=diferente

Q: Como agendar um script para rodar a cada hora no cron?
A: crontab -e
   Adicionar: 0 * * * * bash /caminho/script.sh >> /tmp/log.txt 2>&1
   Formato: minuto hora dia mês dia-semana

---

## Deck: PostgreSQL Diagnosis Flow

Q: Qual é o fluxo de diagnóstico quando há CPU alta no servidor?
A: 1. ps aux --sort=-%cpu | grep postgres  (achar PID no Linux)
   2. SELECT pid, query FROM pg_stat_activity WHERE state != 'idle'  (achar a query)
   3. SELECT pg_cancel_backend(PID)  (cancelar)

Q: Qual é o primeiro comando a rodar em qualquer incidente de banco?
A: systemctl status postgresql  (instalação nativa)
   docker logs --tail 50 pg-lab  (Docker)
   Mostra estado e últimas linhas do log imediatamente.

Q: Como salvar um snapshot do sistema para documentar um incidente?
A: top -b -n 1 -u postgres > /tmp/snapshot-$(date +%H%M).txt
   ps aux | grep postgres >> /tmp/snapshot-$(date +%H%M).txt
   df -h >> /tmp/snapshot-$(date +%H%M).txt

Q: Como verificar se há queries bloqueadas no PostgreSQL?
A: SELECT blocked.pid, blocked.query, blocking.pid
   FROM pg_stat_activity blocked
   JOIN pg_stat_activity blocking
     ON blocking.pid = ANY(pg_blocking_pids(blocked.pid));