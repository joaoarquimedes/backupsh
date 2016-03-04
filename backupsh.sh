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
# Versão 1.0.0:	2014-10-24, João Arquimedes:
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
#
# Joao Costa, Outubro de 2014
#

# recupera o caminho absoluto da onde o scritp está sendo executado
PATH_FULL=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# Importando as configurações
# -----------------------------------------------------------------------
[ ! -e "${PATH_FULL}/backupsh.conf" ] && { echo "*** ERRO ***: Arquivo backupsh.conf não encontrado. Renomear o arquivo backupsh.conf.dist para backupsh.conf"; exit 1;}
source "${PATH_FULL}/backupsh.conf"

# Importando funções básicas
# -----------------------------------------------------------------------
[ ! -e "${PATH_FULL}/backupsh.dep" ] && { echo "*** ERRO ***: Arquivo backupsh.dep não localizado. Necessita para continuar com o script"; exit 1;}
source "${PATH_FULL}/backupsh.dep"

# Binários a serem verificados antes de dar continuidade no restante da execução do script.
BIN="rm tar id wc gzip date mkdir find rsync chown chmod hostname md5sum mount umount mount.cifs"
# Complementando o binário caso seja necessário backup do banco de dados
[ "${BKP_DATABASE}" = "Yes" -a "${DATABASE_TYPE}" = "MySQL" ] && BIN="${BIN} mysql mysqldump"
[ "${BKP_DATABASE}" = "Yes" -a "${DATABASE_TYPE}" = "PostgreSQL" ] && BIN="${BIN} pg_dump psql vacuumdb"

MENSAGEM_USO="
Uso: $(basename "$0") [OPÇÕES]
	Programa parar realizar backup da máquina local. Edite o arquivo para setar as configurações conforme as necessidades.

   OPÇÕES:
   	-d, --debug    Habilita modo debug. Informar o nível do debug [1, 2, 3 ou 4]
	-l, --log      Habilita e gera log gravando em arquivo.
	-s, --sleep    Habilita sleep, dando um tempo entre as execuções dos comandos. Funciona em conjunto com -v
	-v, --verbose  Habilita modo verboso, apresentando mensagens na saída padrão.

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
		-l | --log)		GravaLog=1;;
		-v | --verbose)		Verbose=1;;
		-s | --sleep)		Sleep=1;;
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
	else
		Messages -E "Programa interrompido. Depedência necessária ou binário não localizado."
		Nl
		exit 1
	fi

	Debug 1 "Fim da função $FUNCNAME"
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
			-c | --create )	Create=true;;
			-w | --write )	Write=true;;
			*)              Dir="${1}";;
		esac
		shift
	done

	Debug 2 "Saiu do while. Valores das variáveis locais: \$Create: ${Create}. \$Write: ${Write}. \$Dir: ${Dir}"

	Debug 2 "Checando se o parâmetro do diretório é válido. Parâmetro: \"${Dir}\""
	Messages -L "Verificando diretório: ${Dir}"
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
		Messages -S "Diretório existente."
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
		Messages -A "Diretório inexistente."
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

			Debug 3	"Verificando a variável \$LOG_FILE (${LOG_FILE}) é nula"
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

	local n		# Valor numérico a ser rotacionado
	local p		# Valor do caminho a ser verificado

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
		local filesToRemoveCount=$(find ${p} -mmin +${newN} -name *$(hostname)*gz | wc -l)
		local filesToRemove=$(find ${p} -mmin +${newN} -name *$(hostname)*gz)

		# Setando a barra no final do diretório
		[[ "${p}" =~ \/$ ]] && path="${p}" || path="${p}/"

		Debug 2 "Valor ajustado da variavel \"\$p\": ${p}, adicionando a barra (/) no final: \"\$path\" ${path}"

		Messages -I "Valor em dias a ser mantidos os arquivos: ${n}"
		Messages -I "Quantidade de arquivos encontrados a ser rotacionado: ${filesToRemoveCount}"
		Sleep

		Debug 3 "Valor da variável \$n: ${n}"
        Debug 3 "Valor da variável \$newN: ${newN}"
        Debug 3 "Valor da variável \$filesToRemoveCount: ${filesToRemoveCount}"
		Debug 3 "Localizando a quantidade de arquivos a ser rotacionado com o comando: find ${path} -mmin +${newN} -name *$(hostname)*gz"

		if [ "${n}" -le "${filesToRemoveCount}" ]
		then
			Debug 3 "Executando o comando \"find ${path} -mmin +${newN} -name *$(hostname)*gz -exec rm -r {} \;\" para excluir os arquivos antigos"
		
			Messages -A "Removendo arquivos: ${filesToRemove}"
			WriteLog "Removendo arquivos: ${filesToRemove}"

			Debug 3 "Atualizando o alias para o comando rm"
			alias rm='rm'

			find ${path} -mmin +${newN} -name *$(hostname)*gz -exec rm -rf {} \;
			Sleep
			return 0
		else
			Messages -I "Não há necessidade de rotacionar os backups antigos"
			WriteLog "Não há necessidade de rotacionar os backups antigos"
			return 0
		fi

	else
		Messages -E "Parâmetro inválido para rotacionar o backup. Backup cancelado"
		WriteLog "Parâmetro inválido para rotacionar o backup. Backup cancelado"
		exit 1
	fi
}


# function LocalBackup()
# Função com objetivo de realizar o backup local, salvando
# no dretório especificado na variável no início do script.
function LocalBackup() {
	Debug 1 "Iniciando a função $FUNCNAME"

	Messages -L "Iniciando backup local."
	WriteLog "Iniciando backup local"
	Sleep 2

	# Declarando array
	declare -a allowDir
	local index=0

	# Função local para receber como parâmetros os diretórios a serem compactados.
	function localCheckDir() {
		WriteLog "Verificando diretórios a serem compactados"
		Debug 2 "Entrando no while"
		while test -n "${1}"; do
			Debug 3 "Verificando diretórios ${1} com a função CheckDir."
			CheckDir "${1}"
			if [ $? = 0 ]; then
				allowDir[${index}]="${1}"
				Debug 4 "Diretório ${1} OK. Adicionado ao array allowDir. Valordo array: ${allowDir[$index]}"
				WriteLog "Diretório OK... ${1}"
				let "index++"
			else
				WriteLog "Diretório inválido... ${1}"
			fi
			shift
		done
		Debug 2 "Saiu do while. Valor do Array allowDir: ${allowDir[*]}"
	}

	# Executando função local para verificação dos diretórios
	localCheckDir ${BKP_DIR}

	Debug 2 "Testando se o array é nulo com test -n"
	if [ -n "${allowDir[*]}" ]; then

		Debug 3 "Teste OK. Array não é nulo."

		Messages -S "Verificação concluída com sucesso."
		WriteLog "Verificação concluída com sucesso."
		Sleep 2

		Messages -L "Verificando destino para hospedagem do backup local"
		WriteLog "Verificando destino para hospedagem do backup local: ${LOCAL_PATH}"
		CheckDir "${LOCAL_PATH}" --create --write
		if [ $? != 0 ]; then
			Messages -E "Backup cancelado, destino para hospedagem com erro"
			WriteLog "Backup cancelado, destino para hospedagem com erro"
			Debug 1 "Fim da função $FUNCNAME. Saindo do script com saída 1"
			exit 1
		fi

		# Rotacionando arquivos
		backupRotate ${RETENTION_LOCAL} ${LOCAL_PATH}

		Messages -L "Compactando diretórios ${allowDir[*]}"
		WriteLog "Compactando diretórios ${allowDir[*]}"
		Sleep 2

		# Tratando caminho absoluto para hospedagem do arquivo
		[[ "${LOCAL_PATH}" =~ \/$ ]] && path="${LOCAL_PATH}${COMPACT_FILE}" || path="${LOCAL_PATH}/${COMPACT_FILE}"

		Debug 3 "Compactando diretórios com comando: tar -czf ${path} ${allowDir[*]} --exclude-backups --exclude-caches-all --exclude-vcs --ignore-failed-read --ignore-command-error ${BKP_IGN}"
		tar -czf ${path} ${allowDir[*]} --exclude-backups --exclude-caches-all --ignore-failed-read --ignore-command-error ${BKP_IGN} 2>> ${LOG_FILE_ERROR}
		Messages -S "Arquivo salvo em ${path}"
		Sleep

		md5Sum=$(md5sum ${path})
		if [ $? = 0 ]
		then
			WriteLog "MD5: ${md5Sum}"
			Messages -I "MD5: ${md5Sum}"
			Sleep
		else
			Messages -E "Erro na verificação do arquivo de backup. Backup cancelado"
			WriteLog "Erro na verificação do arquivo de backup. Backup cancelado"
			exit 1
		fi
		
		WriteLog "Size: $(du -h ${path})"
		Messages -I "Size: $(du -h ${path})"
		Sleep
		
		Debug 1 "Saindo da função $FUNCNAME com retorno 0"
		return 0
	fi

	Messages -E "Nenhum diretório válido para compactar. Backup cancelado."
	WriteLog "Nenhum diretório válido para compactar. Backup cancelado."
	Debug 1 "Fim da função $FUNCNAME. Saindo do script com saída 1"
	exit 1
}


# function DatabaseMySQL()
# Função com objetivo de realizar backup das bases de dados a partir do banco
# MySQL
function DatabaseMySQL() {
	[ "${BKP_DATABASE}" = "Yes" -a "${DATABASE_TYPE}" = "MySQL" ] || return
	
	Debug 1 "Iniciando a função $FUNCNAME"

	Messages -L "Iniciando backup das bases de dados com MySQL"
	WriteLog "Iniciando backup das bases de dados com MySQL"
	Sleep

	Messages -I "Varrendo as bases"

	# Tratando caminho absoluto para hospedagem do arquivo
    [[ "${LOCAL_PATH}" =~ \/$ ]] && path="${LOCAL_PATH}" || path="${LOCAL_PATH}/"

	local getDatabases=$(mysql --user="${DATABASE_USER}" --password="${DATABASE_PASS}" -e "SHOW DATABASES;" | tr -d "| " | grep -v Database)

	Debug 2 "Varrendo as bases de dados com o comando: SHOW DATABASES;"
	Debug 2 "Entrando no laço for"
	for db in ${getDatabases}; do
		Debug 3 "Valor da variável \$db: ${db}"
		if [ "${db}" != "information_schema" -a "${db}" != "performance_schema" ]; then
			Messages -L "Realizando dump da base: ${db}"
			WriteLog "Realizando dump da base: ${db}"
			
			local fullname="${DATESTAMP}-$(hostname)-mysql-${db}.sql"

			Debug 4 "Realizando dump da base: ${db} com o comando: mysqldump --user="${DATABASE_USER}" --password="${DATABASE_PASS}" --databases ${db} > ${path}${fullname}"
			mysqldump --user="${DATABASE_USER}" --password="${DATABASE_PASS}" --databases ${db} > ${path}${fullname} 2>> ${LOG_FILE_ERROR}
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
			fi
		fi
	done
	Debug 2 "Saindo do laço for"
}

# function DatabasePostgreSQL()
# Função com objetivo de realizar o backup das bases de dados a partir do
# banco PostgreSQL
function DatabasePostgreSQL() {
        [ "${BKP_DATABASE}" = "Yes" -a "${DATABASE_TYPE}" = "PostgreSQL" ] || return

        Debug 1 "Iniciando a função $FUNCNAME"

        Messages -L "Iniciando backup das bases de dados com PostgreSQL"
        WriteLog "Iniciando backup das bases de dados com PostgreSQL"
        Sleep

        Messages -I "Varrendo as bases"

        # Tratando caminho absoluto para hospedagem do arquivo
        [[ "${LOCAL_PATH}" =~ \/$ ]] && path="${LOCAL_PATH}" || path="${LOCAL_PATH}/"

        # Concedendo permissão de escrita para usuário postgres no direório de backup
        chown -R postgres. ${path}

        local getDatabases=$(su - postgres -c "psql -l -U \"${DATABASE_USER}\"" | sed -n 4,/\eof/p | grep -v '(' | awk {'print $1'} | grep -v '|' | grep -v template0)

        Debug 2 "Varrendo as bases de dados com o comando: su - postgres -c psql;"
        Debug 2 "Entrando no laço for"
        for db in ${getDatabases}; do
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
                fi

                local fullname="${DATESTAMP}-$(hostname)-postgresql-${db}.sql"

                Messages -I "Realizando dump da base: ${db}"
                WriteLog "Realizando dump da base: ${db}"
                Debug 3 "Realizando dump da base com o comando: "
                su - postgres -c "pg_dump -U \"${DATABASE_USER}\" ${db} -f ${path}${fullname}" 2>> ${LOG_FILE_ERROR}
                if [ $? = 0 ]; then
                        Messages -S "Dump ${db} --> Compactando..."
                        WriteLog "Dump realizado com sucesso: ${db}"
                        Debug 4 "Dump: ${db} OK. Compactando a base com o comando gzip -qf ${path}${fullname}"
                        gzip -qf ${path}${fullname}
                        WriteLog "MD5: $(md5sum ${path}${fullname}.gz)"
						Messages -I "MD5: $(md5sum ${path}${fullname}.gz)"
						WriteLog "Size: $(du -h ${path}${fullname}.gz)"
						Messages -I "Size: $(du -h ${path}${fullname}.gz)"
                else
                        Messages -E "Erro ao realizar o dump na base ${db}"
                        WriteLog --error "Erro ao realizar o dump na base ${db}"
                fi
        done
}


# function MountDir()
# Função com objetivo de montar o diretório responsável pela hospedagem dos
# arquivos de backup. Esta função irá consultar as variáveis de usuário, senha
# servidor e ponto de montagem.
function MountDir() {
	Debug 1 "Iniciando a função $FUNCNAME"

	Messages -L "Iniciando a montagem do diretório para backup remoto."
	WriteLog "Iniciando a montagem do diretório para backup remoto."
	Messages -L "Verificando o ponto de montagem"
	Sleep
	CheckDir "${SRC_MOUNT}" --create
	if [ $? != 0 ]; then
		Messages -E "Erro ao verificar o ponto de montagem. Backup cancelado"
		WriteLog "Erro ao verificar o ponto de montagem. Backup cancelado"
		Debug 1 "Erro gerado pelo último comando executado, saindo do script com saída 1"
		exit 1
	fi

	Messages -L "Mapeando diretório \"${DST_MOUNT}\" do servidor ${SERVER}"
	Sleep
	if [ ! "$(mount | grep ${DST_MOUNT})" ]; then
		Messages -A "Montando diretório"
		WriteLog "Montando diretório"
		Debug 2 "Montando diretório. Comando: mount -t cifs //${SERVER}/${DST_MOUNT} ${SRC_MOUNT} -o username=${USER},password=${PASS},iocharset=utf8"
		Sleep
		mount -t cifs //${SERVER}/${DST_MOUNT} ${SRC_MOUNT} -o username=${USER},password=${PASS},iocharset=utf8
		if [ $? = 0 ]; then
			Messages -S "Diretório montado com sucesso. Verificando permissão de escrita"
			WriteLog "Diretório montado com sucesso. Verificando permissão de escrita"
			Sleep
			CheckDir "${SRC_MOUNT}" --write
			if [ $? != 0 ]; then
				Messages -E "Diretório sem permissão de escrita. Backup cancelado."
				WriteLog "Diretório sem permissão de escrita. Backup cancelado."
				Debug 3 "Erro do último comando executado. saindo do script com saída 1"
				exit 1
			fi
		else
			Messages -E "Erro na montagem do diertório do servidor ${SERVER}"
			WriteLog "Erro na montagem do diertório do servidor ${SERVER}"
			Debug 3 "Erro do último comando executado. saindo do script com saída 1"
			exit 1
		fi
	else
		Messages -S "Diretório já montado. Verificando permissão de escrita."
		WriteLog "Diretório já montado. Verificando permissão de escrita."
		Sleep
		CheckDir "${SRC_MOUNT}" --write
		if [ $? != 0 ]; then
			Messages -E "Diretório sem permissão de escrita. Backup cancelado."
			WriteLog "Diretório sem permissão de escrita. Backup cancelado."
			Debug 3 "Erro do último comando executado. saindo do script com saída 1"
			exit 1
		fi
	fi
	WriteLog "Diretório OK"
	Debug 1 "Saindo da função $FUNCNAME"
	return 0
}


# function UmountDir()
# Função com objetivo de desmontar o diretório de backup remoto.
function UmountDir() {
	Debug 1 "Iniciando a funcação $FUNCNAME"
	Messages -L "Desmontando diretório remoto"
	WriteLog "Desmontando diretório remoto"
	Sleep
	Debug 2 "Desmontando a unidade ${SRC_MOUNT} com umount"
	[ "$(mount | grep ${DST_MOUNT})" ] && umount ${SRC_MOUNT}
}


# function RemoteSync()
# Função com objetivo de realizar a cópia dos arquivos para o servidor
# remoto.
function RemoteSync() {
	Debug 1 "Iniciando a função $FUNCNAME"
	Messages -L "Sincronizando arquivos para servidor remoto: ${SERVER}"
	WriteLog "Sincronizando arquivos para servidor remoto: ${SERVER}"
	Sleep

	# Verificando se foi informado a barra no final da variável
	[[ "${SRC_MOUNT}" =~ \/$ ]] && pathToSync="${SRC_MOUNT}$(hostname)/" || pathToSync="${SRC_MOUNT}/$(hostname)/"

	Debug 2 "Tratando a variável do caminho do backup remoto:"
	Debug 2 "Valor da variável \$SRC_MOUNT: ${SRC_MOUNT}"
	Debug 2 "Valor da variável local \$pathToSync: ${pathToSync}"

	CheckDir ${pathToSync} --create --write
	if [ $? = 0 ]; then
		# Tratando caminho de origem
		[[ "${LOCAL_PATH}" =~ \/$ ]] && localPath="${LOCAL_PATH}" || localPath="${LOCAL_PATH}/"

		backupRotate ${RETENTION_REMOTE} ${pathToSync}

		Debug 3 "Realizando sincronismo para o servidor remoto com comando rsync -avHK ${localPath} ${pathToSync}"

		Messages -L "Sincronizando diretório ${localPath} para ${pathToSync}"
		Sleep

		rsync -aqHK ${localPath} ${pathToSync}
		if [ $? = 0 ]; then
			Messages -S "Sincronismo realizado com sucesso"
			WriteLog "Sincronismo realizado com sucesso"
			Sleep
		else
			Messages -E "Erro no processo do sincronismo. Backup cancelado"
			WriteLog "Erro no processo do sincronismo. Backup cancelado"
			exit 1
		fi
	else
		Messages -E "Erro na verificação do diretório para backup remoto. Backup cancelado"
		WriteLog "Erro na verificação do diretório para backup remoto. Backup cancelado"
		exit 1
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
}

# function AddCommand()
# Função com objetivo de executar o arquivo externo para complementar este script de backup
# com comandos específicos a uma rotina em particular.
# No mesmo diretório basta criar o arquivo extamente
function AddCommand(){
		[ ! -e "${PATH_FULL}/backupsh.add" ] && return 0
		Debug 1 "Iniciando a função $FUNCNAME"
		Messages -I "Arquivo adicional localizado. Executando o script para complementar o backup"; Sleep
		WriteLog "Arquivo adicional localizado. Executando o script para complementar o backup"
		bash ${PATH_FULL}/backupsh.add
		Debug 1 "Saindo da função $FUNCNAME"
}

clear
Messages "------------------------------"
Messages " Iniciando Programa de Backup"
Messages "------------------------------"
Sleep; Nl

CheckBin; Nl
WriteLog --checkdir; Nl

WriteLog "Iniciando o processo de backup."

LocalBackup; Nl
DatabaseMySQL; Nl
DatabasePostgreSQL; Nl
MountDir; Nl
RemoteSync; Nl
AddCommand; Nl
UmountDir; Nl
SetPermissions

WriteLog "Fim do processo de backup"
WriteLog "-------------------------"
Messages "Fim do processo de backup"
Messages "-------------------------"
