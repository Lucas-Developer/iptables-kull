#!/usr/bin/env bash
###################################
# IPtables por Kum Traceroute     #
# Contato: +55 (14) 98820-8320    #
###################################

function firewall_version() {
  if [ ! "$quiet" ] ; then
    echo "[+] IPTables Kull 1.0.5"
  fi
}

function firewall_help() {
  firewall_version
  echo "[+] Uso: firewall <opção>"
  echo " :: help         :: mostra essa página de ajuda"
  echo " :: start        :: inicia as regras"
  echo " :: stop         :: apaga e retorna as políticas padrões ao normal"
  echo " :: status       :: mostra se o iptables está ativo ou inativo"
  echo " :: config       :: editar as configurações"
  echo "Veja https://github.com/kumroute/iptables-kull/ para mais informações"
}

# Retorna o caminho até o arquivo de configuração
function caminho_config() {

  # Cria se não existir
  : ${CONFIG_KULL:="/etc/kull/config"}

  # Retorna o caminho até o arquivo de config
  echo "$CONFIG_KULL"

}

# Verifica erros, de acordo com o $1, recebe $? como argumento
# Se $2 existir, então output somente em erros
function verificar_erro() {

  if [ $1 -eq 0 ] ; then
    # Se não tiver o quiet
    if [ ! "$quiet" ] && [ ! "$2" ] ; then
      printf " [\e[32mok\e[0m]\n"
    fi
  else
    if [ ! "$quiet" ] && [ ! "$2" ] ; then
      printf " [\e[31merror\e[0m]\n" ; exit
    # Se tiver, muda o output
    else
      echo " :: Algum erro foi detectado, code: $1" ; exit
    fi
  fi

}

function firewall_status() {
  firewall_version
  # Valor da primeira regra (politica padrão do INPUT)
  var=`iptables -S | head -1 | awk {'print $3'}`
  if [ "$var" == "ACCEPT" ] ; then
    echo " :: está inativo"
  else
    echo " :: está ativo"
  fi
}

function firewall_config() {

  # Usa a função caminho_config
  caminho_config=`caminho_config`

  # Utiliza o editor configurado na config para editar
  editor=`cat $caminho_config | grep "editor_config" | \
    awk {'print $2'}`

  echo "$caminho_config $editor"
  # Se não existir a linha que especifica o editor, usar o vim
  if [ ! "$editor" ] ; then
    sudo vim $caminho_config

  else
    sudo $editor $caminho_config
  fi

}

# Regras que devem ter em todas as configurações
function carregar_regras() {

  if [ ! "$quiet" ] ; then
    printf "[+] Trocando políticas padrões" ; fi
  iptables -P INPUT DROP ; verificar_erro "$?" "somente erros"
  iptables -P FORWARD DROP ; verificar_erro "$?" "somente erros"
  if [ "${1,,}" != "input" ] ; then

    iptables -P OUTPUT DROP ; verificar_erro "$?"

    # Liberar conexões estabelecidas e relacionadas
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    verificar_erro "$?" "somente erros"

    # Loop back, locahost
    iptables -A OUTPUT -o lo -j ACCEPT
    verificar_erro "$?" "somente erros"

  else
    iptables -P OUTPUT ACCEPT ; verificar_erro "$?"
  fi

  # Liberar conexões estabelecidas e relacionadas
  iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
  verificar_erro "$?" "somente erros"

  # Loop back, localhost
  iptables -A INPUT -i lo -j ACCEPT
  verificar_erro "$?" "somente erros"

}

function firewall_up() {

  firewall_down

  # Carregar as regras de base
  carregar_regras "$1"

  # Usa a função caminho_config
  caminho_config=`caminho_config`

  # Quantidade de linhas do arquivo config
  num_linhas=`wc -l $caminho_config | awk {'print $1'}`

  # Numero da linha da primeira divisão (ex: [Kernel])
  linha_inicio=`cat $caminho_config | cat --number | grep "\[" | \
    head -1 | awk {'print $1'}`

  n=$[linha_inicio+1]

  # J simboliza todas as 4 possiveis divisões do arquivo config
  for ((j=1 ; j<=4 ; ++j)) ; do

    # Enquanto ainda tiver linhas para ler
    while [ $n -le $num_linhas ] ; do

      # Conteudo da linha $n
      linha=`cat $caminho_config | head -$n | tail -1`

      # Se a linha não for newline (\n) / vazia
      if [ "$linha" ] ; then

        # Se a linha não começar outra divisão (ex: [Port])
        verificar=`echo $linha | cut -c 1`
        if [ "$verificar" == "[" ] ; then break ; fi

        # Chama a função de acordo com a divisão, passa como
        # argumento $linha
        nome_divisao=`cat $caminho_config | grep "\[" | head -$j | \
          tail -1 | sed -e 's/\[//g' | sed -e 's/\]//g'`
        conteudo=`echo "$linha" | sed -e 's/_/ /g'`

        # $2 = input, ou seja, o user quer somente carregar as
        # regras de input
        if [ "${2,,}" == "input" ] ; then
          echo "$conteudo" | grep -q "output"
          if [ $? -ne 0 ] ; then
            $nome_divisao $conteudo
          fi
        else
            $nome_divisao $conteudo
        fi

      fi

    n=$[n+1]
    done

  n=$[n+1]
  done
 

}

function firewall_down() {

  if [ ! "$quiet" ] ; then
    printf "[+] Apagando as regras" ; fi
  iptables -F ; verificar_erro "$?" "somente erros"
  iptables -X ; verificar_erro "$?" "somente erros"
  iptables -Z ; verificar_erro "$?"

  if [ ! "$quiet" ] ; then
    printf "[+] Trocando políticas padrões" ; fi
  iptables -P INPUT ACCEPT ; verificar_erro "$?" "somente erros"
  iptables -P FORWARD ACCEPT ; verificar_erro "$?" "somente erros"
  iptables -P OUTPUT ACCEPT ; verificar_erro "$?"

}

# Divisão [Kernel] do arquivo de config
# Recebe o nome da opção ($1) e o valor ($2) como argumento
function Kernel() {

  opcao=`echo "$*" | awk {'print $NF'}`
  arquivo=`echo "$*" | sed -e 's/: yes//g' | sed -e 's/: no//g' | \
    sed -e 's/ /_/g'`

  if [ "opcao" == "yes" ] ; then
    echo "1" > /proc/sys/net/ipv4/${arquivo}
  elif [ "opcao" == "no" ] ; then
    echo "0" > /proc/sys/net/ipv4/${arquivo}
  fi

}

# Divisão [Options] do arquivo de config
# Recebe o nome da opção ($1) e o valor ($2) como argumento
function Options() {

  # Ping é um caso especial
  if [ "${1,,}" == "ping" ] ; then
    shift
    if [ "${1,,}" == "reply" ] ; then
      protocolo="-p icmp --icmp-type 0"
    else
      protocolo="-p icmp --icmp-type 8"
    fi
  else
    protocolo="${1,,}"
  fi

  # Verifica se é INPUT, FORWARD ou OUTPUT
  if [ "${2,,}" == "input:" ] ; then
    chain="-A INPUT"
  elif [ "${2,,}" == "output:" ] ; then
    chain="-A OUTPUT"
  elif [ "${2,,}" == "forward:" ] ; then
    chain="-A FORWARD"
  else
    verificar_erro "2021" "1"
  fi

  # Verifica se é para aceitar, rejeitar ou "dropar"
  if [ "${3,,}" == "allow" ] ; then
    acao="-j ACCEPT"
  elif [ "${3,,}" == "deny" ] ; then
    acao="-j REJECT"
  elif [ "${3,,}" == "drop" ] ; then
    acao="-j DROP"
  else
    verificar_erro "2020" "1"
  fi

  iptables $chain $protocolo $acao
  verificar_erro "$?" "1" 
 
}

# Divisão [Protect] do arquivo de config
# Recebe o nome da opção ($1) e o valor ($2) como argumento
function Protect() {

  # Function verificar_erro com printf para o usuário
  function print_status() {
    if [ ! "$quiet" ] ; then
      printf "[+] Carregando proteção contra $2"
    fi
    verificar_erro "$1"
  }

  # Pegar o nome da interface wlan
  caminho_config=`caminho_config`
  interface=`cat $caminho_config | grep "interface_wlan" | \
    awk {'print $2'}`

  if [ "${1,,}" == "syn-flood:" ] ; then
    if [ "${2,,}" == "yes" ] ; then
      iptables -A INPUT -p tcp --syn -m limit --limit 2/s -j ACCEPT
      print_status "$?" "syn-flood"
    fi
  fi

  if [ "${1,,}" == "ip-spoofing:" ] ; then
    if [ "${2,,}" == "yes" ] ; then
      iptables -A INPUT -s 172.16.0.0/16 -i $interface -j DROP
      verificar_erro "$?" "somente erros"
      iptables -A INPUT -s 192.168.0.0/24 -i $interface -j DROP
      print_status "$?" "ip-spoofing"
    fi
  fi

  if [ "${1,,}" == "port-scan:" ] ; then
    if [ "${2,,}" == "yes" ] ; then
      iptables -N SCANNER
      verificar_erro "$?" "somente erros"
      iptables -A SCANNER -j DROP
      verificar_erro "$?" "somente erros"
      iptables -A INPUT -p tcp --tcp-flags ALL FIN,URG,PSH -i $interface -j SCANNER
      verificar_erro "$?" "somente erros"
      iptables -A INPUT -p tcp --tcp-flags ALL NONE -i $interface -j SCANNER
      verificar_erro "$?" "somente erros"
      iptables -A INPUT -p tcp --tcp-flags ALL ALL -i $interface -j SCANNER
      verificar_erro "$?" "somente erros"
      iptables -A INPUT -p tcp --tcp-flags ALL FIN,SYN -i $interface -j SCANNER
      verificar_erro "$?" "somente erros"
      iptables -A INPUT -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -i $interface -j SCANNER
      verificar_erro "$?" "somente erros"
      iptables -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST -i $interface -j SCANNER
      verificar_erro "$?" "somente erros"
      iptables -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -i $interface -j SCANNER
      print_status "$?" "port-scan"
    fi
  fi

  if [ "${1,,}" == "death-ping:" ] ; then
    if [ "${2,,}" == "yes" ] ; then
      iptables -A INPUT -p icmp --icmp-type 0 -m limit --limit 1/s -j RETURN
      print_status "$?" "death-ping"
    fi
  fi

  if [ "${1,,}" == "block-fragments:" ] ; then
   if [ "${2,,}" == "yes" ] ; then
    iptables -A INPUT -f -j DROP
    print_status "$?" "fragments"
   fi
  fi
  
}

# Divisão [Port] do arquivo de config
# Recebe o nome da opção ($1) e o valor ($2) como argumento
function Port() {

  if [ "${1,,}" == "portknock:" ] ; then

    # Para pegar as portas do portknock (linha acima do portknock:)
    caminho_config=`caminho_config`

    # Numero da linha do portknock:
    num_linha=`cat $caminho_config | cat --number | grep "$*" | \
      awk {'print $1'}`

    # Portas do portknock
    linha_portas=$[num_linha-1]
    portas_portknock=`cat $caminho_config | head -$linha_portas | \
      tail -1 | sed -e 's/ //g' | sed -e 's/ports_portknock://g' | \
      sed -e 's/,/ /g'`

    # Se não existir a opção ports_portknock no config
    if [ ! "$portas_portknock" ] ; then
      verificar_erro "5080" "1"
    fi

    if [ ! "$quiet" ] ; then
      printf "[+] Carregando fases do portknock" ; fi

    # Criar as fases do portknock de acordo com as portas_portknock
    # Quantidade de fases (qnt de portas)
    qnt_portas=`echo $portas_portknock | wc -w`

    if [ $qnt_portas -gt 1 ] ; then

      for ((i=2 ; i<=$qnt_portas ; ++i)) ; do

        # K seria a porta da fase anterior
        k=$[k-1]

        iptables -N INTO-FASE${i}
        verificar_erro "$?" "somente erros"
        iptables -A INTO-FASE${i} -m recent --name FASE${k} --remove
        verificar_erro "$?" "somente erros"
        iptables -A INTO-FASE${i} -m recent --name FASE${i} --set
        verificar_erro "$?" "somente erros"
        iptables -A INTO-FASE${i} -j LOG --log-prefix "FIREWALL: ${i}- fase portknock :  "
        verificar_erro "$?" "somente erros"
 
      done

      # Primeira fase
      iptables -A INPUT -m recent --update --name FASE1
      verificar_erro "$?" "somente erros"

      for ((i=1 ; i<=$qnt_portas ; ++i)) ; do

        # K seria a porta da fase anterior
        k=$[i-1]

        # Porta da fase do portknock $i
        porta_i=`echo $portas_portknock | sed -e 's/ /\n/g' | \
          head -$i | tail -1`

        if [ $i -eq 1 ] ; then
          iptables -A INPUT -p tcp --dport ${porta_i} -m recent --set --name FASE1
          verificar_erro "$?" "somente erros"
        else
          iptables -A INPUT -p tcp --dport ${porta_i} -m recent --rcheck --seconds 60 --name FASE${k} -j INTO-FASE${i}
          verificar_erro "$?" "somente erros"
        fi

      numero_de_fases="$qnt_portas"

      done

      # Dizendo que foi um sucesso
      verificar_erro "0"


    # Se o usuário só especificar uma porta no ports_portknock:
    else

      iptables -A INPUT -m recent --update --name FASE1
      iptables -A INPUT -p tcp --dport $portas_portknock -m recent --set --name FASE1

      numero_de_fases="1"

    fi

    # Portas para proteger, valor da opção portknock: ($2)
    portas_para_proteger=`echo $* | sed -e 's/portknock://g' | sed -e 's/ //g' | \
      sed -e 's/,/ /g'`

    # Quantidade de portas para proteger
    qnt_proteger=`echo $portas_para_proteger | wc -w`

    if [ ! "$quiet" ] ; then
      printf "[+] Carregando regras para o portknock" ; fi

    for ((i=1 ; i<=$qnt_proteger ; ++i)) ; do

      # Porta para proteger de acordo com $i
      porta_proteger=`echo $portas_para_proteger | sed -e 's/ /\n/g' | \
        head -$i | tail -1`

      iptables -A INPUT -p tcp --dport ${porta_proteger} -m recent --rcheck --seconds 600 --name FASE${numero_de_fases} -j ACCEPT
      verificar_erro "$?" "somente erros"

    done

    # Dizendo que foi um sucesso
    verificar_erro "0"


  # Ignorar se for a opção ports_porknock:
  elif [ "${1,,}" == "ports" ] ; then
    ignorar="somente para ignorar"

  # Se não for portas para proteger com o portknock
  # Então, é só aceitar
  else
    
    # Ex: allow_input_tcp: -> allow input tcp
    opcao=`echo $* | sed -e 's/ /\n/g'`

    # Ação (allow, deny ou drop)
    valor=`echo "$opcao" | head -1`
    if [ "${valor,,}" == "allow" ] ; then
      acao="-j ACCEPT"
    elif [ "${valor,,}" == "deny" ] ; then
      acao="-j REJECT"
    elif [ "${valor,,}" == "drop" ] ; then
      acao="-j DROP"
    else
      verificar_erro "4040" "1"
    fi

    # Chain (input, output ou forward)
    valor=`echo "$opcao" | head -2 | tail -1`
    if [ "${valor,,}" == "input" ] ; then
      chain="-A INPUT"
    elif [ "${valor,,}" == "output" ] ; then
      chain="-A OUTPUT"
    elif [ "${valor,,}" == "forward" ] ; then
      chain="-A FORWARD"
    else
      verificar_erro "4041" "1"
    fi

    # Protocolo (tcp ou udp)
    # Por padrão, é TCP
    valor=`echo "$opcao" | head -3 | tail -1`
    if [ "${valor,,}" == "udp:" ] ; then
      protocolo="-p udp"
    else
      protocolo="-p tcp"
    fi

    # Portas (Ex: 40, 12, 1444 -> 40 12 1444)
    portas=`echo $* | sed -e 's/[a-z_A-Z]*//g' | sed -e 's/://g' | \
      sed -e 's/ //g' | sed -e 's/,/ /g' | sed -e 's/ /\n/g'`

    # Quantidade de portas
    qnt_portas=`echo "$portas" | wc -l`

    if [ ! "$quiet" ] ; then
      printf "[+] Liberando portas para livre uso" ; fi

    for ((ii=1; ii<=$qnt_portas ; ++ii)) ; do

      # Porta de acordo com o $ii
      porta=`echo "$portas" | head -$ii | tail -1`

      iptables $chain $protocolo --dport ${porta} $acao
      verificar_erro "$?" "somente erros"

    done

    # Dizendo que foi um sucesso
    verificar_erro "0"

  fi

}


echo "$*" | grep -q "quiet"
if [ $? -eq 0 ] ; then
  quiet="verdadeiro"
fi

if [ "${1,,}" == "start" ] ; then
  if [ "${2,,}" == "input" ] ; then
    # Carregar somente as regras de INPUT
    firewall_up input
  else
    firewall_version
    firewall_up
  fi

elif [ "${1,,}" == "stop" ] ; then
  firewall_version
  firewall_down

elif [ "${1,,}" == "status" ] ; then
  firewall_status

elif [ "${1,,}" == "config" ] ; then
  firewall_config

else
  firewall_help
fi

