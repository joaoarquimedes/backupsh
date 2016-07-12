#!/bin/bash
#
# backupsh.sh - Backup local das aplicações
#
# Autor         : Joao Arquimedes de S. Costa
# Manutenção    : o mesmo
#
# -----------------------------------------------------------------------
#
# Este programa tem por objetivo realizar backups locais das aplicações
# compactando, armazenando em um diretório local e posteriormente levando
# estes arquivos a um servidor remoto.
# Todas as configurações são realizadas alterando somente as variáveis
# globais ou aceitando alguns parâmetros na execussão.
#
# -----------------------------------------------------------------------
#
# Histórico:
#
# Versão 1.0.0: 2014-10-24, João Arquimedes:
#               - Versão inicial do programa. Definindo as funcionalidades básicas.
#
# Versão 1.0.1: 2015-08-28, João Arquimedes:
#               - Ajustado a função backupRotate caso queira manter somente 1 dia de backup.
#               - Alterado a ordem de manter os backups, onde será primeiramente removido e depois realizado um novo backup.
#               - Exportado para outro arquivo as funções genéricas e de configurações.
#
# Versão 1.1.0: 2015-08-31, João Arquimedes:
#               - Criado a função para receber o backup das bases de dados via MySQL.
#
# Versão 1.2.0: 2015.09.01, João Arquimedes:
#               - Adicionado a opção de log de erro. WriteLog --error "Mensagem de error" ou 2>> ${LOG_FILE_ERROR}.
#               - Redirecionado a saída de erro do banco de dados (mysqldump) e tar para o log de erro.
#               - Adicionado as funções DatabasePostgreSQL() e SetPermissions().
#               - Adicionado a condição de execução somente como root.
#
# Versão 1.2.1: 2015.09.02, João Arquimedes:
#               - Adicionado a verificação dos arqiuvos backupsh.conf e backupsh.dep antes de dar continuidade.
#               - Atualizado o formato do nome do arquivo de backup para data e hora (YYYYmmdd-HHMM)
#
# Versão 1.2.2: 2015.09.08, João Arquimedes:
#               - Ajustado o rotacionamento dos arquivos de backup para buscar os arquivos anteriores com 60 minutos a menos.
#
# Versão 1.3.0: 2015.09.09, João Arquimedes:
#               - Adicionado a funcionalidade de poder adicionar comandos extras ao script em arquivo externo, para não precisar alterar o arquivo backupsh.sh.
#
# Versão 1.3.1: 2015.09.11, João Arquimedes:
#               - Adicionado nos Log's o processo de criação do diretório de backup.
#               - Verificando se o comando md5 foi realizado com sucesso.
#               - Adicionado a barra (/) no final do diretório a ser rotacionado os arquivos
#
# Versão 1.3.2: 2015.09.15, João Arquimedes:
#               - Ajustado a variável do sincronismo remoto para descartar o curinga asterisco (*).
#               - Adicionado MD5 e Size nos backups dos banco de dados.
#
# Versão 1.3.3: 2015.10.01, João Arquimedes:
#               - Ajustado o rotacionamento dos arquivos de backup para buscar os arquivos anteriores com 120 minutos a menos.
#
# Versão 1.3.4: 2015.11.13, João Arquimedes:
#               - Alterado a ordem da execução do script adicional (backupsh.add) e o momento em que o disco remoto é montado.
#               - Removido a opção "--exclude-vcs" como comando default do tar. Adicionado nas configurações (backupsh.conf) como padrão.
#
# Versão 1.3.5: 2015.12.18, João Arquimedes:
#               - Alterado novamente a ordem do backup remoto com o script adicional (backupsh.add).
#               - Removido a função "UmountDir" de dentro da função "RemoteSync" e adicionado para execução após a função "AddCommand"
#
# Versão 1.3.6: 2016.01.22, João Arquimedes:
#               - Especificado os arquivos a serem rotacionados na função "backupRotate()" com o parâmetro "-name *$(hostname)*gz" no comando find.
#
# Versão 1.4.0: 2016.05.22, João Arquimedes:
#               - Adicionado backup remoto como opcional.
#               - Reconhecendo tipo do sistema operacional.
#               - Adicionado opcional para poder realizar backup do banco de dados PostgreSQL e MySQL no mesmo script.
#
# Versão 1.4.1: 2016.07.02, João Arquimedes:
#               - Adicionado controle de execução, travando o processo com lock e PID.
#               - Suportando backup de pastas e arquivos
#               - Suporte a backup parcial -p | --partial
#               - Adicionado a funcionalidade de notificação por email com a função SendMail
#
# Versão 1.4.2: 2016.07.05, João Arquimedes:
#               - Adicionado alternativa de backup com ZIP caso o comando TAR não funcione.
#               - Ajustado a função backupRotate
#               - Removendo arquivo caso ocorra erro no backup
#
# Versão 1.4.3: 2016.07.07, João Arquimedes:
#               - Adicionado verificação de retorno no backup adicional. function AddCommand().
#               - Adicionado descrição do host e melhoria nas notificações por email.
#
# Versão 1.4.4: 2016.07.08, João Arquimedes:
#               - Alterado a forma do dump do postgres para --format=c
#
# Versão 1.4.5: 2016.07.08, João Arquimedes:
#               - Debug retordo do comando tar.
#
#
# Joao Costa, Outubro de 2014
#

# recupera o caminho absoluto da onde o scritp está sendo executado
PATH_FULL=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# Importando as configurações
# -----------------------------------------------------------------------
[ ! -e "${PATH_FULL}/backupsh.conf" ] && { echo "*** ERRO ***: Arquivo backupsh.conf não encontrado. Renomear o arquivo backupsh.conf.dist para backupsh.conf"; exit 1; }
source "${PATH_FULL}/backupsh.conf"

# Importando funções básicas
# -----------------------------------------------------------------------
[ ! -e "${PATH_FULL}/backupsh.dep" ] && { echo "*** ERRO ***: Arquivo backupsh.dep não localizado. Necessita para continuar com o script"; exit 1; }
source "${PATH_FULL}/backupsh.dep"

# Binários a serem verificados antes de dar continuidade no restante da execução do script.
BIN="rm tar id wc gzip date mkdir find chown chmod egrep hostname md5sum flock"
# Complementando o binário caso seja necessário backup do banco de dados
[ "${BKP_DATABASE}" = "Yes" -a "${DATABASE_TYPE}" = "MySQL" ] || [ "${BKP_DATABASE}" = "All" ] && BIN="${BIN} mysql mysqldump"
[ "${BKP_DATABASE}" = "Yes" -a "${DATABASE_TYPE}" = "PostgreSQL" ] || [ "${BKP_DATABASE}" = "All" ] && BIN="${BIN} pg_dump psql vacuumdb"
[ "${WIN_BKP_REMOTE}" = "Yes" ] && BIN="${BIN} mount.cifs mount umount rsync"
[ "${SEND_MAIL}" = "Yes" -a ! "$(grep "CentOS release 5" /etc/redhat-release)" ] && BIN="${BIN} mailx" || BIN="${BIN} nail"

MENSAGEM_USO="
Uso: $(basename "$0") [OPÇÕES]
   Programa parar realizar backup da máquina local. Edite o arquivo para setar as configurações conforme as necessidades.

   OPÇÕES:
   -d, --debug    Habilita modo debug. Informar o nível do debug [1, 2, 3 ou 4]
   -l, --log      Habilita e gera log gravando em arquivo.
   -s, --sleep    Habilita sleep, dando um tempo entre as execuções dos comandos. Funciona em conjunto com -v
   -v, --verbose  Habilita modo verboso, apresentando mensagens na saída padrão.
   -p, --partial  Realiza backup parcial somente dos arquivos alterados recentemente.
   --mailtest     Envia um email de teste.

   -h, --help     Mostra opções e finaliza
   -V, --version  Mostra versão e finaliza
"

# Tratamento das opções de linha de comando
while test -n "$1"
do
   case "$1" in
      -d | --debug)
         shift
         case "$1" in
            1) deb="$1";;
            2) deb="$1";;
            3) deb="$1";;
            4) deb="$1";;
            *)
               echo "Valor inválido para -d"
               exit 1
            ;;
         esac
      ;;
      -l | --log)       GravaLog=1;;
      -v | --verbose)   Verbose=1;;
      -s | --sleep)     Sleep=1;;
      -p | --partial)   Partial=true;;
      --mailtest)       MailTest=true;;
      -h | --help)
         echo "$MENSAGEM_USO"
         exit 0
      ;;
      -V | --version)
         echo -n $(basename "$0")
         # Extrai a versão do cabeçalho do programa
         grep '^# Versão ' "$0" | tail -1 | cut -d : -f 1 | tr -d \#
         exit 0
      ;;
      *)
         if test -n "$1"
            then
               echo "Opção inválida: $1"
               exit 1
         fi
      ;;
   esac
   shift
done


# Verifica se o usuário é root
if [ "$EUID" -ne 0 ]; then
   Messages -E "Favor, executar este script como root"
   exit 1
fi


# Gera o PID do programa e cria o arquivo lock
PIDFILE="/var/run/$(basename $0).pid"
LOCKFILE="/var/lock/$(basename $0).lock"
LOCKFD=99
_lock()             { flock -$1 $LOCKFD; }
_no_more_locking()  { _lock u; _lock xn && rm -f ${LOCKFILE} && rm -r ${PIDFILE}; }
_prepare_locking()  { eval "exec ${LOCKFD}>\"${LOCKFILE}\""; trap _no_more_locking EXIT; }
_prepare_locking
_lock xn || { Messages -E "Programa $(basename $0) já em execução. PID: $(cat ${PIDFILE}). Lock: ${LOCKFILE}"; exit 1 ; }
echo $$ > ${PIDFILE}


# function CheckBin()
# Função responsável para verificar os programas básicos necessários antes
# de dar continuidade no restante do script. Estes programas são informados
# na variável BIN.
function CheckBin() {
   Debug 1 "Iniciado a função $FUNCNAME"
   Messages -L "Verificando dependências."
   Sleep 2

   pass=true

   Debug 2 "Entrando no laço for para tratar a variável \$BIN. Conteúdo: $BIN"
   for i in $BIN
   do
      Debug 3 "Testando se a variável \$i existe, com -f. Valor: $i"
      if [ -f "$(which $i)" ]
      then
         Debug 4 "Existe. Valor: $(which $i)"
         Messages -S "$i... $(which $i)"
      else
         Debug 4 "Não existe. Valor: $(which $i)"
         Messages -W "Binário não localizado: $i"
         pass=false
      fi
      Sleep 0.6
   done
   Debug 2 "Fim do laço for"


   if [ "$pass" = "true" ]
   then
      Messages -S "Verificação concluída com sucesso."
      Sleep 2
      Nl
      return 0
   else
      Messages -E "Programa interrompido. Depedência necessária ou binário não localizado."
      SendMail "Backup não realizado. Depedência necessária ou binário não localizado."
      Nl
      exit 1
   fi
}


# function GetOSVersion()
# Função com objetivo de recuperar o tipo e verão do sistema operacional
function GetOSVersion() {

   local OS="unknown"

   File[0]=/etc/redhat-release
   File[1]=/etc/debian_version

   for i in ${File[*]}
   do
      if [ -e $i ]; then
         [[ $(grep "CentOS Linux release 7" $i) ]]   && OS="CentOS 7"
         [[ $(grep "CentOS release 6" $i) ]]         && OS="CentOS 6"
         [[ $(grep "CentOS release 5" $i) ]]         && OS="CentOS 5"
         [[ $(grep "8\." $i) ]]                      && OS="Debian 8"
      fi
    done

   echo $OS
   return 0
}


# function SendMail()
# Função com objetivo de realizar notificações por email
# Recebe como parâmetro o conteúdo da mensagem.
# Exemplo:
# SendMail "Não foi possível realizar backup do arquivo desejado"
function SendMail() {
   [ "${SEND_MAIL}" = "Yes" ] || return
   [ ! -z "${1}" ] || return

   Messages -A "Realizando notificação por email"
   Messages -I "Destinatário: ${SMTP_RECEIVER}"

   WriteLog "Notificando usuário por e-amil..."
   WriteLog "Destinatário: ${SMTP_RECEIVER}"
   WriteLog "Mensagem: ${1}"

   local CurrentDate=$(date "+%Y/%m/%d %H:%M:%S")
   local CurrentUser=$(id -u -n)
   local Content="
Notificação do Script de Backup $(basename $0)
Data: $CurrentDate
Host: $(hostname)
Descrição: ${HOST_DESC}
Versão do Script: $(grep '^# Versão ' "$0" | tail -1 | cut -d : -f 1 | tr -d \#)
------------------------------------------------------------------------------
${1}
------------------------------------------------------------------------------
"

   # Realiza o envio da mensagem
   [ "$(GetOSVersion)" != "CentOS 5" ] && { local Command="mailx" ; } || { local Command="nail" ; }

   echo "${Content}" | $Command -s "${SMTP_SUBJECT}" -S smtp="smtp://${SMTP_HOST}:${SMTP_PORT}" -S from="${SMTP_SENDER_NAME} <${SMTP_SENDER}>" ${SMTP_RECEIVER}
}


# Function CheckFile()
# Funçào com objetivo de verificar se o arquivo existe e se é válido para
# realizar o backup
# Recebe como parâmetro o nome do arquivo.
# Exemplo:
# ChechFile "/var/log/messages"
function CheckFile() {
   Debug 1 "Iniciando a função $FUNCNAME"

   Debug 2 "Validando arquivo com a opção -f do if. Se é um arquivo normal"
   if [[ -f $1 ]]
   then
      Debug 3 "condição then. Opção validada como verdade. return 0"
      return 0 
   else
      Debug 3 "condição else. Opção validada como falso. return 1"
      return 1
   fi
}


# function CheckDir()
# Função com objetivo de verificar e criar o diretório.
# Recebe como parâmetro o caminho do diretório.
# Exemplo:
# CheckDir "/var/log/backuplog"
#
# A criação do diretório é opcional. Para criar, caso o diertório
# não exista, basta informar o parâmetro -c ou --create.
# Exemplo:
# CheckDir "/var/log/backuplog" --create
#
# A verificação de permissão de escrita também é opcional. Para
# verificar basta informar o parâmetro -w ou --write.
function CheckDir() {
   Debug 1 "Iniciando a função $FUNCNAME"

   local Create=false
   local Write=false
   local Dir=

   Debug 2 "Verificando se recebeu parâmetros. Entrando no while"
   while test -n "${1}"
   do
      Debug 2 "Valor do \$1: ${1}"
      case "${1}" in
         -c | --create )   Create=true;;
         -w | --write )    Write=true;;
         *)                Dir="${1}";;
      esac
      shift
   done

   Debug 2 "Saiu do while. Valores das variáveis locais: \$Create: ${Create}. \$Write: ${Write}. \$Dir: ${Dir}"

   Debug 2 "Checando se o parâmetro do diretório é válido. Parâmetro: \"${Dir}\""
   if [[ ! "${Dir}" =~ ^(\/|\.|_)?{1}[\.]?{1}[A-Za-z0-9]+ ]]
   then
      Debug 3 "Parâmetro do diretório inválido: \"${Dir}\""
      Debug 3 "Saindo da função $FUNCNAME com return 1"
      Messages -W "Parâmetro do diretório inválido: \"${Dir}\""
      return 1
   fi

   Debug 2 "Verificando se o diretório ${Dir} existe. if com -d"
   Sleep
   if [ -d "${Dir}" ]
   then
      Debug 2 "Sucesso na verificação."
      Sleep 0.5

      if [ "${Write}" = true ]; then
         Debug 2 "Verificando permissão de escrita no diretório com -w."
         Messages -L "Verificando permissão de escrita."
         Sleep 2
         if [ -w "${Dir}" ]
         then
            Debug 3 "Sucesso, possui permissão de escrita no diretório."
            Messages -S "Permissão de escrita."
            Debug 3 "Saindo da função $FUNCNAME com return 0"
            Sleep 2
            return 0
         else
            Debug 3 "Erro, não possui permissão de escrita no diretório. Saindo da $FUNCNAME com return 1."
            Messages -W "Sem permissão de escrita no diretório."
            Debug 3 "Saindo da função $FUNCNAME com return 1"
            Sleep 2
            return 1
         fi
      fi
      Debug 2 "Saindo da função $FUNCNAME com return 0"
      return 0
      Sleep 2
   else
      Debug 2 "Falha na verificação, diretório não existe."
      #Messages -A "Diretório inexistente."
      Sleep 2

      if [ "${Create}" = true ]
         then
         Debug 2 "Tentando criar diretório com \$(mkdir ${Dir})"
         if $(mkdir -p ${Dir} 2> ${LOG_FILE_ERROR})
         then
            Debug 3 "Sucesso. Diretório criado com sucesso."
            Messages -S "Diretório criado com sucesso: ${Dir}"
            WriteLog "Diretório criado com sucesso: ${Dir}"
            Debug 3 "Saindo da função $FUNCNAME com return 0"
            Sleep 2
            return 0
         else
            Debug 3 "Falha ao criar o diretório"
            Messages -W "Falha ao criar o diretório: ${Dir}"
            WriteLog "Falha ao criar o diretório: ${Dir}"
            Debug 3 "Saindo da função $FUNCNAME com return 1."
            Sleep 3
            return 1
         fi
      fi
      Debug 2 "Saindo da função $FUNCNAME com return 1"
      return 1
   fi
   Debug 1 "Saiu do if."
   Debug 1 "Fim da função $FUNCNAME"
   return 1
}


# Funções específicas
# -----------------------------------------------------------------------
# Funções de acordo para cada tipo de uso.
#
#
# function WriteLog()
# Função com objetivo de gravar em log os passos realizados pelo script.
# Exemplo:
# WriteLog "Mensagem a ser gravada."
#
# Para checar se a escrita ocorrerá com sucesso, basta informar o
# parâmetro --checkdir.
# Exemoplo:
# WriteLog --checkdir
#
# Para gravar no log de erro, basta informar o parâmetro --error. Exemplo:
# WriteLog --error "Mensagem de erro"
#
#
# ATENÇÃO: Para que os logs possam ser escritos, tem que haver a checagem
# de diretório ao menos uma vez e no início do script (WriteLog --checkdir).
#
function WriteLog() {
   [ "${GravaLog}" = 1 ] || return

   Debug 1 "Inicado a função $FUNCNAME"

   if [ "$1" = "--checkdir" ]
   then
      Debug 2 "Recebido o parâmetro --checkdir. Verificando diretório."
      Messages -L "Verificando diretório para escrita dos logs."
      Sleep 2
      CheckDir "$LOG_PATH" --write --create
      if [ $? = 0 ]
      then
         Debug 3 "Retorno igual a 0 do último comando executado."
         Messages -S "Verificação concluída com sucesso."

         Debug 3  "Verificando a variável \$LOG_FILE (${LOG_FILE}) é nula"
         [ -z "$LOG_FILE" ] && Messages -W "Parâmetro LOG_FILE em branco" && return 1

         Debug 3 'Setando a variável local $setdir=0 para que o log possa ser escrito'
         setdir=0
      else
         Debug 3 "Retorno diferente de 0 do último comando executado."
         Messages -W "Continuando o script sem os logs."
         setdir=1
         Debug 3 "Saindo da função $FUNCNAME com return 1"
         return 1
      fi
   elif [ "$1" = "--error" -a ! -z "$2" -a "$setdir" = 0 ]
   then
      Debug 2 "Escrevendo em log de error."
      local CurrentDate=$(date "+%Y/%m/%d %H:%M:%S")
      local CurrentUser=$(id -u -n)
      echo "${CurrentDate} ${CurrentUser} - ${2}" >> ${LOG_FILE_ERROR}
   elif [ ! -z "$1" -a "$setdir" = 0 ]
   then
      Debug 2 "Escrevendo em log."
      local CurrentDate=$(date "+%Y/%m/%d %H:%M:%S")
      local CurrentUser=$(id -u -n)
      echo "${CurrentDate} ${CurrentUser} - ${1}" >> ${LOG_FILE}
   fi
   Debug 1 "Fim da função $FUNCNAME"
   return 0
}


# function backupRotate()
# Função com objetivo de rotacionar o backup.
# Recebe como parâmetro o valor da quantidade total em dias de backups
# que devem ser mantidos e o caminho onde os arquivos estão hospedados.
# Exemplo:
# backupRotate ${RETENTION_LOCAL} ${LOCAL_PATH}
function backupRotate() {
   Debug 1 "Iniciando a função $FUNCNAME"

   local n     # Valor numérico a ser rotacionado
   local p     # Valor do caminho a ser verificado

   # Recuperando os parâmetros informados na chamada da função
   Debug 2 "Entrando no laço"
   while test -n "${1}"; do
      Debug 3 "Valor do parâmetro \$1: ${1}"
      # Verificando se é um número
      [[ $1 =~ ^[[:digit:]]{1}+$ ]] && [ $1 -gt 0 ] && n=$1
      # Verificando se é um caminho diretório
      [[ "${1}" =~ ^(\/|\.|_)?{1}[\.]?{1}[A-Za-z0-9]+ ]] && p=$1
      Debug 3 "Valor da variável local \$n: ${n}"
      Debug 3 "Valor da variável local \$p: ${p}"
      shift
   done
   Debug 2 "Saiu do laço"

   Debug 2 'Realizando teste das variáveis $n e $p'
   if [ -n "${n}" -a -n "${p}" ]; then
      Debug 2 'Teste realizado com sucesso. Valores de $n e $p diferente de nulo'
      Messages -L "Localizando arquivos a serem rotacionados"
      WriteLog "Localizando arquivos a serem rotacionados"
      Sleep

      # Ajustando o valor de n para remover os arquivos
      local newN=$((${n}*24*60-120)) # Convertendo o valor em dia para minutos e diminuindo duas horas

      local filesToRemoveCount=$(find ${p} -type f -mmin +${newN} | egrep "*.$(hostname)*.*(gz|tar|tgz|zip|backup)$" | wc -l)
      local filesToRemove=$(find ${p} -type f -mmin +${newN} | egrep "*.$(hostname)*.*(gz|tar|tgz|zip|backup)$")

      # Setando a barra no final do diretório
      [[ "${p}" =~ \/$ ]] && path="${p}" || path="${p}/"

      Debug 2 "Valor ajustado da variavel \"\$p\": ${p}, adicionando a barra (/) no final: \"\$path\" ${path}"

      Messages -I "Valor em dias a ser mantidos os arquivos: ${n}"
      Messages -I "Quantidade de arquivos encontrados a ser rotacionado: ${filesToRemoveCount}"
      Sleep

      Debug 3 "Valor da variável \$n: ${n}"
      Debug 3 "Valor da variável \$newN: ${newN}"
      Debug 3 "Valor da variável \$filesToRemoveCount: ${filesToRemoveCount}"

      if [ "${n}" -le "${filesToRemoveCount}" ]
      then
         Messages -A "Removendo arquivos rotacionados"
         WriteLog "Removendo arquivos rotacionados"
         alias rm='rm'
         for i in ${filesToRemove}
         do
            Messages -L "Removido... $i"
            WriteLog "Removido... $i"
            rm -rf $i
         done
         Sleep
         return 0
      else
         Messages -I "Não há necessidade de rotacionar os backups antigos"
         WriteLog "Não há necessidade de rotacionar os backups antigos"
         return 0
      fi

   else
      Messages -E "Parâmetro inválido para rotacionar o backup. Favor, verificar as opções utilizadas."
      WriteLog "Parâmetro inválido para rotacionar o backup. Favor, verificar as opções utilizadas."
      SendMail "Parâmetro inválido para rotacionar o backup. Favor, verificar as opções utilizadas."
      return 1
   fi
}


# function LocalBackup()
# Função com objetivo de realizar o backup local, salvando
# no dretório especificado na variável $BKP_DIR.
function LocalBackup() {
   Debug 1 "Iniciando a função $FUNCNAME"

   Messages -L "Validando caminhos a serem realizados os backups."
   WriteLog "Validando caminhos a serem realizados os backups."
   Sleep 2

   # Declarando array
   declare -a allowBackup
   local index=0

   # Função local para receber como parâmetros os diretórios e arquivos a serem compactados.
   function localCheckBackup() {
      Debug 2 "Entrando no while"
      while test -n "${1}"; do
         Debug 3 "Verificando diretórios/arquivos ${1} com a função CheckDir e CheckFile."

         if CheckDir "${1}"
         then
            Debug 4 "Caminho ${1} OK. Adicionado ao array allowBackup. Valordo array: ${allowBackup[$index]}"
            allowBackup[${index}]="${1}"
            Messages -S "Validado: ${1}"
            WriteLog "Validado: ${1}"
            let "index++"
         elif CheckFile "${1}"
         then
            Debug 4 "Caminho ${1} OK. Adicionado ao array allowBackup. Valordo array: ${allowBackup[$index]}"
            allowBackup[${index}]="${1}"
            Messages -S "Validado: ${1}"
            WriteLog "Validado: ${1}"
            let "index++"
         else
            Messages -W "Caminho desconhecido para backup -> ${1}"
            WriteLog --error "Caminho desconhecido para backup -> ${1}"
         fi
         shift
      done
      Debug 2 "Saiu do while. Valor do Array allowBackup: ${allowBackup[*]}"
   }

   # Executando função local para verificação dos diretórios/arquivos
   localCheckBackup ${BKP_DIR}

   Debug 2 "Testando se o array é nulo com test -n"
   if [ -n "${allowBackup[*]}" ]; then
      Debug 3 "Teste OK. Array não é nulo."
      Messages -S "Verificação concluída com sucesso."
      WriteLog "Verificação concluída com sucesso."
      Sleep 2

      Messages -L "Verificando destino para hospedagem do backup local"
      WriteLog "Verificando destino para hospedagem do backup local: ${LOCAL_PATH}"
      CheckDir "${LOCAL_PATH}" --create --write
      if [ $? != 0 ]; then
         Messages -E "Backup cancelado, destino para hospedagem com erro."
         WriteLog "Backup cancelado, destino para hospedagem com erro."
         SendMail "Backup cancelado, destino para hospedagem com erro."
         Debug 1 "Fim da função $FUNCNAME. Saindo do script com saída 1"
         exit 1
      fi

      # Rotacionando arquivos
      backupRotate ${RETENTION_LOCAL} ${LOCAL_PATH}

      Messages -L "Compactando arquivos ${allowBackup[*]}"
      WriteLog "Compactando arquivos ${allowBackup[*]}"
      Sleep 2

      # Tratando caminho absoluto para hospedagem do arquivo
      [[ "${LOCAL_PATH}" =~ \/$ ]] && path="${LOCAL_PATH}${COMPACT_FILE}" || path="${LOCAL_PATH}/${COMPACT_FILE}"

      # Tratando nome do arquivo para remover extensão caso apresentado na variável do arquivo conf
      [[ "${path}" =~ (tar\.gz|\.tgz|\.gz|\.zip)$ ]] && path=$(echo $path | sed -r 's/(\.tgz|\.tar\.gz|\.gz|\.zip)$//')

      # De imediato, definindo a extensão como tgz.
      local ext_file="tgz"

      if [[ "${Partial}" = true ]]
      then
         local path="${path}-Partial"
         local tarOPTS='--newer-mtime='2 days ago''
      else
         local path="${path}-Full"
         local tarOPTS=""
      fi

      local tarToCentOS5="tar -czf ${path}.${ext_file} ${allowBackup[*]} --ignore-failed-read --ignore-zeros --ignore-case ${tarOPTS} ${BKP_IGN}"
      local tarToNewOS="tar -czf ${path}.${ext_file} ${allowBackup[*]} --ignore-failed-read --ignore-command-error --absolute-names --exclude-backups --exclude-caches-all ${tarOPTS} ${BKP_IGN}"

      #Definindo comando a ser executado
      if [[ $(GetOSVersion) != "CentOS 5" ]]
      then
         local compactCommand="${tarToNewOS}"
      else
         Messages -I "CentOS 5 detectado"
         local compactCommand="${tarToCentOS5}"
      fi

      Debug 3 "Compactando arquivos com comando: ${compactCommand}"
      [[ "${Partial}" = true ]] && Messages -C "Realizando backup parcial"

      # Executando comando tar
      ${compactCommand} 2>> ${LOG_FILE_ERROR}
      if [ true ]; then
      #if [ $? = 0 ]; then
      # #################################################################################################################
      #
      # LOCAL COMENTADO PARA DEBUGAR OS POSSÍVEIS RETORNOS DO COMANDO TAR.
      # EXIGE MELHORIA PARA CONSIDERAR SE O COMANDO FOI EXECUTADO COM SUCESSO OU SE HOUVE PENAS MENSAGEM DE ALERTA.
      #
      # #################################################################################################################
      
         Messages -S "Arquivo salvo em ${path}.${ext_file}"
         WriteLog "Arquivo salvo em: ${path}.${ext_file}"
         Sleep
      else
         Messages -W "Erro ao realizar o backup com o comando tar. Tentando compactar com o comando zip"
         WriteLog --error "Erro ao realizar o backup com o comando tar. Tentando compactar com o comando zip"
         [[ -f ${path}.${ext_file} ]] && rm -rf ${path}.${ext_file}
   
         if [ -f "$(which zip)" ]; then
            Messages -I "Realizando a compactação com programa zip"
            WriteLog "Realizando a compactação com programa zip"

            # Definindo nova extensão
            local ext_file="zip"

            # Verificando se o backup é parcial
            if [[ "${Partial}" = true ]]
            then
               Messages -I "Realizando backup com zip somente de arquivos alterados recentemente"
               WriteLog "Realizando backup com zip somente de arquivos alterados recentemente"

               # Executando comando para compactação
               #find ${allowBackup[*]} -mtime -2 -exec zip ${path}.${ext_file} '{}' + > /dev/null 2>> ${LOG_FILE_ERROR}
               zip -ruq ${path}.${ext_file} ${allowBackup[*]} $BKP_IGN > /dev/null 2>> ${LOG_FILE_ERROR}
               if [ $? = 0 ]; then
                  Messages -S "Arquivo salvo em ${path}.${ext_file}"
                  WriteLog "Arquivo salvo em ${path}.${ext_file}"
                  SendMail "Backup realizado com sucesso com programa ZIP. Houve erro ao tentar realizar o backup com o programa TAR. Arquivo salvo em ${path}.${ext_file}"
               else
                  Messages -E "Erro ao realizar compactação dos arquivos tanto com comando tar e zip. Backup cancelado."
                  WriteLog "Erro ao realizar compactação dos arquivos tanto com comando tar e zip. Backup cancelado."
                  SendMail "Erro ao realizar compactação dos arquivos tanto com comando tar e zip. Backup cancelado."
                  exit 1
               fi
            else
               # Executando comando zip
               Debug 3 "Compactando via zip com comando: zip -q ${path}.${ext_file} ${allowBackup[*]} $BKP_IGN"
               zip -rq ${path}.${ext_file} ${allowBackup[*]} $BKP_IGN > /dev/null 2>> ${LOG_FILE_ERROR}
               if [ $? = 0 ]; then
                  Messages -S "Arquivo salvo em ${path}.${ext_file}"
                  WriteLog "Arquivo salvo em ${path}.${ext_file}"
                  SendMail "Backup realizado com sucesso com programa ZIP. Houve erro ao tentar realizar o backup com o programa TAR. Arquivo salvo em ${path}.${ext_file}"
               else
                  Messages -E "Erro ao realizar compactação dos arquivos tanto com comando tar e zip. Backup cancelado."
                  WriteLog "Erro ao realizar compactação dos arquivos tanto com comando tar e zip. Backup cancelado."
                  SendMail "Erro ao realizar compactação dos arquivos tanto com comando tar e zip. Backup cancelado."
                  [[ -f ${path}.${ext_file} ]] && rm -rf ${path}.${ext_file}
                  exit 1
               fi
            fi
         else
            Messages -E "Programa zip não localizado. Backup cancelado."
            WriteLog "Programa zip não localizado. Backup cancelado."
            SendMail "Programa zip não localizado. Backup cancelado."
            exit 1
         fi
      fi

      local md5Sum=$(md5sum ${path}.${ext_file} | cut -d " " -f 1)
      if [ $? = 0 ]; then
         WriteLog "MD5: ${md5Sum}"
         Messages -I "MD5: ${md5Sum}"
         Sleep
      else
         Messages -E "Erro na verificação do arquivo de backup."
         WriteLog --error "Erro na verificação do arquivo de backup com md5sum. Necessita de análise técnica."
         SendMail "Erro na verificação do arquivo de backup com md5sum. Necessita de análise técnica."
         return 1
      fi
      
      local size=$(du -h ${path}.${ext_file} | tr '\t' ' ' | cut -d " " -f1)
      WriteLog "Size: ${size}"
      Messages -I "Size: ${size}"
      Sleep
      
      Debug 1 "Saindo da função $FUNCNAME com retorno 0"
      Nl
      return 0
   fi

   Messages -E "Nenhum diretório/arquivo válido para compactar. Backup cancelado."
   WriteLog "Nenhum diretório/arquivo válido para compactar. Backup cancelado."
   SendMail "Nenhum diretório/arquivo válido para compactar. Backup cancelado."
   Debug 1 "Fim da função $FUNCNAME. Saindo do script com saída 1"
   exit 1
}


# function DatabaseMySQL()
# Função com objetivo de realizar backup das bases de dados a partir do banco
# MySQL
function DatabaseMySQL() {

   [ "${BKP_DATABASE}" = "Yes" -a "${DATABASE_TYPE}" = "MySQL" ] || [ "${BKP_DATABASE}" = "All" ] || return 1

   Debug 1 "Iniciando a função $FUNCNAME"
   Messages -L "Iniciando backup das bases de dados com MySQL"
   WriteLog "Iniciando backup das bases de dados com MySQL"
   Sleep

   Messages -I "Varrendo as bases"

   # Tratando caminho absoluto para hospedagem do arquivo
   [[ "${LOCAL_PATH}" =~ \/$ ]] && path="${LOCAL_PATH}" || path="${LOCAL_PATH}/"

   Debug 2 "Comando para mapear todas as bases de dados: mysql --user=\"${DATABASE_USER}\" --password=\"${DATABASE_PASS}\" -e \"SHOW DATABASES;\" | tr -d \"| \" | grep -v Database | egrep -v \"^sys$\""

   getDatabases () {
      (mysql --user="${DATABASE_USER}" --password="${DATABASE_PASS}" -e "SHOW DATABASES;" | tr -d "| " | grep -v Database | egrep -v "^sys$") 2>> ${LOG_FILE_ERROR}
   }

   if [[ ! $(getDatabases) ]]; then
      Messages -E "Erro ao listar as bases de dados."
      WriteLog --error "Erro ao listar as bases de dados."
      SendMail "Erro ao listar as bases de dados MySQL."
      Nl
      return 1
   fi   

   local error=0

   Debug 2 "Entrando no laço for"
   for db in $(getDatabases); do
      Debug 3 "Valor da variável \$db: ${db}"
      if [ "${db}" != "information_schema" -a "${db}" != "performance_schema" ]; then
         Messages -L "Realizando dump da base: ${db}"
         WriteLog "Realizando dump da base: ${db}"
         
         local fullname="${DATESTAMP}-$(hostname)-mysql-${db}.sql"

         Debug 4 "Realizando dump da base: ${db} com o comando: mysqldump --user="${DATABASE_USER}" --password="${DATABASE_PASS}" --databases ${db} > ${path}${fullname}"
         (mysqldump --user="${DATABASE_USER}" --password="${DATABASE_PASS}" --databases ${db} > ${path}${fullname}) 2>> ${LOG_FILE_ERROR}
         if [ $? = 0 ]
         then
            Messages -S "${db} -> Compactando..."
            WriteLog "Dump OK: ${db}"
            Debug 4 "Dump: ${db} OK. Compactando a base com o comando gzip -qf ${path}${fullname}"
            gzip -qf ${path}${fullname}
            WriteLog "MD5: $(md5sum ${path}${fullname}.gz)"
            Messages -I "MD5: $(md5sum ${path}${fullname}.gz)"
            WriteLog "Size: $(du -h ${path}${fullname}.gz)"
            Messages -I "Size: $(du -h ${path}${fullname}.gz)"
         else
            Messages -W "Erro ao realizar o dump da base de dados: ${db}"
            WriteLog --error "Erro ao realizar backup da base de dados: ${db}"
            SendMail "Erro ao realizar backup da base de dados (MySQL): ${db}"
            error=1
         fi
      fi
   done
   Debug 2 "Saindo do laço for"
   Nl
   [ $error = 0 ] && return 0 || return 1
}

# function DatabasePostgreSQL()
# Função com objetivo de realizar o backup das bases de dados a partir do banco PostgreSQL
function DatabasePostgreSQL() {

   [ "${BKP_DATABASE}" = "Yes" -a "${DATABASE_TYPE}" = "PostgreSQL" ] || [ "${BKP_DATABASE}" = "All" ] || return 1

   Debug 1 "Iniciando a função $FUNCNAME"
   Messages -L "Iniciando backup das bases de dados com PostgreSQL"
   WriteLog "Iniciando backup das bases de dados com PostgreSQL"
   Sleep

   Messages -I "Listando as bases de dados"

   # Tratando caminho absoluto para hospedagem do arquivo
   [[ "${LOCAL_PATH}" =~ \/$ ]] && path="${LOCAL_PATH}" || path="${LOCAL_PATH}/"

   # Concedendo permissão de escrita para usuário postgres no direório de backup
   chown -R postgres. ${path}

   getDatabases () {
      (su - postgres -c "psql -l -U \"${DATABASE_USER}\"" | sed -n 4,/\eof/p | grep -v '(' | awk {'print $1'} | grep -v '|' | grep -v template0)
   }

   if [[ $(getDatabases) ]]; then
      for db in $(getDatabases); do
         Messages -L "Base localizada... ${db}"
         WriteLog "Base localizada... ${db}"
      done
   else
      Messages -E "Erro ao listar as bases de dados."
      WriteLog --error "Erro ao listar as bases de dados."
      SendMail "Erro ao listar as bases de dados (PostgreSQL)."
      Nl
      return 1
   fi

   # Variável para verificar se houve erro em algum procedimento do laço
   local error=0

   Debug 2 "Entrando no laço for"
   for db in $(getDatabases); do

      if [ "${DATABASE_PGSQL_VACUUM}" = "Yes" ]
      then
         Messages -I "Realizando vacuum na base de dados: ${db}"
         WriteLog "Realizando vacuum na base de dados: ${db}"
         Debug 3 "Realizando vacuum na base com o comando: su - postgres -c \"/usr/bin/vacuumdb -U \"${DATABASE_USER}\" -d $db\""
         su - postgres -c "/usr/bin/vacuumdb -U \"${DATABASE_USER}\" -d ${db}" 2>> ${LOG_FILE_ERROR}
         if [ $? = 0 ]; then
            Messages -S "Vacuum realizado com sucesso: ${db}"
            WriteLog "Vacuum realizado com sucesso: ${db}"
         else
            Messages -E "Erro ao realizar o vacuum na base ${db}"
            WriteLog --error "Erro ao realizar o vacuum na base ${db}"
            SendMail "Erro ao realizar o vacuum na base (PostgreSQL): ${db}"
            error=1
         fi
      else
         Messages -W "Realizando dump da base \"${db}\" sem realizar vacuumdb"
         WriteLog "Realizando dump da base \"${db}\" sem realizar vacuumdb"
      fi

      local fullname="${DATESTAMP}-$(hostname)-postgresql-${db}.backup"

      Messages -I "Realizando dump da base: ${db}"
      WriteLog "Realizando dump da base: ${db}"
      su - postgres -c "pg_dump --format=c -U \"${DATABASE_USER}\" ${db} -f ${path}${fullname}" 2>> ${LOG_FILE_ERROR}
      if [ $? = 0 ]; then
         Messages -S "Dump realizado com sucesso: ${db}"
         WriteLog "Dump realizado com sucesso: ${db}"

         local md5Sum=$(md5sum ${path}${fullname} | cut -d " " -f 1)
         WriteLog "MD5: ${md5Sum}"
         Messages -I "MD5: ${md5Sum}"

         local size=$(du -h ${path}${fullname} | tr '\t' ' ' | cut -d " " -f1)
         WriteLog "Size: ${size}"
         Messages -I "Size: ${size}"
      else
         Messages -E "Erro ao realizar o dump na base ${db}"
         WriteLog --error "Erro ao realizar o dump na base ${db}"
         SendMail "Erro ao realizar o dump na base (PostgreSQL): ${db}"
         error=1
      fi
   done
   Debug 2 "Saindo do laço for"
   Nl
   [ $error = 0 ] && return 0 || return 1
}


# function MountDir()
# Função com objetivo de montar o diretório responsável pela hospedagem dos
# arquivos de backup. Esta função irá consultar as variáveis de usuário, senha
# servidor e ponto de montagem.
function MountDir() {
   [ "${WIN_BKP_REMOTE}" = "Yes" ] || return 1

   Debug 1 "Iniciando a função $FUNCNAME"

   Messages -L "Iniciando a montagem do diretório para backup remoto."
   WriteLog "Iniciando a montagem do diretório para backup remoto."
   Messages -L "Verificando o ponto de montagem"
   Sleep
   CheckDir "${WIN_SRC_MOUNT}" --create
   if [ $? != 0 ]; then
      Messages -E "Erro ao verificar o ponto de montagem."
      WriteLog "Erro ao verificar o ponto de montagem."
      SendMail "Erro ao verificar/criar o ponto de montagem para backup remoto."
      Debug 1 "Erro gerado pelo último comando executado, retornando 1"
      return 1
   fi

   Messages -L "Mapeando diretório \"${WIN_DST_MOUNT}\" do servidor ${WIN_SERVER}"
   Debug 2 "Verificando ponto de montagem com: grep ${WIN_SRC_MOUNT}"
   Sleep
   if [ ! "$(mount | grep ${WIN_SRC_MOUNT})" ]; then
      Messages -I "Montando diretório"
      WriteLog "Montando diretório"
      Debug 2 "Montando diretório. Comando: mount -t cifs //${WIN_SERVER}/${WIN_DST_MOUNT} ${WIN_SRC_MOUNT} -o username=${WIN_USER},password=${WIN_PASS},iocharset=utf8"
      Sleep
      mount -t cifs //${WIN_SERVER}/${WIN_DST_MOUNT} ${WIN_SRC_MOUNT} -o username=${WIN_USER},password=${WIN_PASS},iocharset=utf8
      if [ $? = 0 ]; then
         Messages -S "Diretório montado com sucesso. Verificando permissão de escrita"
         WriteLog "Diretório montado com sucesso. Verificando permissão de escrita"
         Sleep
         CheckDir "${WIN_SRC_MOUNT}" --write
         if [ $? != 0 ]; then
            Messages -E "Diretório sem permissão de escrita."
            WriteLog "Diretório sem permissão de escrita."
            SendMail "Diretório para backup remoto sem permissão de escrita."
            Debug 3 "Erro do último comando executado. return 1"
            return 1
         fi
      else
         Messages -E "Erro na montagem do diertório do servidor ${WIN_SERVER}"
         WriteLog "Erro na montagem do diertório do servidor ${WIN_SERVER}"
         SendMail "Erro na montagem do diertório do servidor ${WIN_SERVER}"
         Debug 3 "Erro do último comando executado. return 1"
         return 1
      fi
   else
      Messages -S "Diretório já montado. Verificando permissão de escrita."
      WriteLog "Diretório já montado. Verificando permissão de escrita."
      Sleep
      CheckDir "${WIN_SRC_MOUNT}" --write
      if [ $? != 0 ]; then
         Messages -E "Diretório sem permissão de escrita."
         WriteLog "Diretório sem permissão de escrita."
         SendMail "Diretório para backup remoto sem permissão de escrita."
         Debug 3 "Erro do último comando executado. return 1"
         return 1
      fi
   fi
   WriteLog "Diretório OK"
   Debug 1 "Saindo da função $FUNCNAME"
   Nl
   return 0
}


# function UmountDir()
# Função com objetivo de desmontar o diretório de backup remoto.
function UmountDir() {
   [ "${WIN_BKP_REMOTE}" = "Yes" ] || return 1

   Debug 1 "Iniciando a funcação $FUNCNAME"
   Messages -L "Desmontando diretório remoto"
   WriteLog "Desmontando diretório remoto"
   Sleep
   Debug 2 "Desmontando a unidade ${WIN_SRC_MOUNT} com umount"
   umount ${WIN_SRC_MOUNT} && { Nl; return 0; }
}


# function RemoteSync()
# Função com objetivo de realizar a cópia dos arquivos para o servidor
# remoto.
function RemoteSync() {
   [ "${WIN_BKP_REMOTE}" = "Yes" ] || return 1

   Debug 1 "Iniciando a função $FUNCNAME"
   Messages -L "Sincronizando arquivos para servidor remoto: ${WIN_SERVER}"
   WriteLog "Sincronizando arquivos para servidor remoto: ${WIN_SERVER}"
   Sleep

   # Verificando se foi informado a barra no final da variável
   [[ "${WIN_SRC_MOUNT}" =~ \/$ ]] && pathToSync="${WIN_SRC_MOUNT}$(hostname)/" || pathToSync="${WIN_SRC_MOUNT}/$(hostname)/"

   Debug 2 "Tratando a variável do caminho do backup remoto:"
   Debug 2 "Valor da variável \$SRC_MOUNT: ${WIN_SRC_MOUNT}"
   Debug 2 "Valor da variável local \$pathToSync: ${pathToSync}"

   CheckDir ${pathToSync} --create --write
   if [ $? = 0 ]; then
      # Tratando caminho de origem
      [[ "${LOCAL_PATH}" =~ \/$ ]] && localPath="${LOCAL_PATH}" || localPath="${LOCAL_PATH}/"

      backupRotate ${WIN_RETENTION_REMOTE} ${pathToSync}

      Debug 3 "Realizando sincronismo para o servidor remoto com comando rsync -avHK ${localPath} ${pathToSync}"

      Messages -L "Sincronizando diretório ${localPath} para ${pathToSync}"
      Sleep

      rsync -aqHK ${localPath} ${pathToSync}
      if [ $? = 0 ]; then
         Messages -S "Sincronismo realizado com sucesso"
         WriteLog "Sincronismo realizado com sucesso"
         Sleep
         Nl
         return 0
      else
         Messages -E "Erro no processo do sincronismo."
         WriteLog "Erro no processo do sincronismo."
         SendMail "Erro no processo do sincronismo com backup remoto."
         return 1
      fi
   else
      Messages -E "Erro na verificação do diretório para backup remoto."
      WriteLog "Erro na verificação do diretório para backup remoto."
      SendMail "Erro na verificação do diretório para backup remoto."
      return 1
   fi
}

# function SetPermissions()
# Função com objetivo de setar as permissões adequadas aos backups para acesso
# somente root
function SetPermissions(){
   Messages -I "Setando as permissões no diretório ${LOCAL_PATH}"
   chown -R root. ${LOCAL_PATH}
   chmod -R 700 ${LOCAL_PATH}
   find ${LOCAL_PATH} -type f -exec chmod 600 {} \;
   Nl
   return 0
}

# function AddCommand()
# Função com objetivo de executar o arquivo externo para complementar este script de backup
# com comandos específicos a uma rotina em particular.
# No mesmo diretório basta criar o arquivo extamente
function AddCommand(){
   [ -e "${PATH_FULL}/backupsh.add" ] || return

   Debug 1 "Iniciando a função $FUNCNAME"
   Messages -I "Arquivo adicional localizado. Executando o script para complementar o backup"; Sleep
   WriteLog "Arquivo adicional localizado. Executando o script para complementar o backup"
   bash ${PATH_FULL}/backupsh.add
   if [ $? -eq 0 ]
   then
      Messages -S "Backup adicional realizado com sucesso"
      WriteLog "Backup adicional realizado com sucesso"
      Sleep
      Nl
      return 0
   else
      Messages -W "Backup adicional com erro"
      WriteLog --error "Backup adicional com erro"
      SendMail "Backup adicional com erro"
      Sleep
      Nl
      return 1
   fi
   Debug 1 "Saindo da função $FUNCNAME"
}


clear
Messages "------------------------------"
Messages " Iniciando Programa de Backup"
Messages "$(grep '^# Versão ' "$0" | tail -1 | cut -d : -f 1 | tr -d \#). PID: $(cat ${PIDFILE})"
Messages " Linux: $(GetOSVersion)"
Messages "------------------------------"
Nl

CheckBin

# Verifica se necessita somente de um teste de envio de email
if [ "${MailTest}" = "true" -a "${SEND_MAIL}" != "Yes" ]
then
   Messages -E "Favor, configurar o arquivo backupsh.conf antes de realizar teste de envio de email."
   exit 1
elif [ "${MailTest}" = "true" -a "${SEND_MAIL}" = "Yes" ]
then
   Messages -C "Realizando somente teste de envio de email"
   SendMail "Email enviado como testes (opção $(basename $0) --mailtest).
Favor, desconsiderar esta notificação."
   exit 0
fi

WriteLog --checkdir; Nl
WriteLog "Iniciando o processo de backup."
LocalBackup
DatabaseMySQL
DatabasePostgreSQL
MountDir && RemoteSync
AddCommand
UmountDir

SetPermissions

WriteLog "Fim do processo de backup"
WriteLog "-------------------------"
Messages "Fim do processo de backup"
Messages "-------------------------"
