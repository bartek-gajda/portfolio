#!/usr/bin/env python3

# program run several commends on linux servers
# commands are sent and executed using nornir library
# collected results are displayed in colours using colorama
#
# (c) Bartosz Gajda - 2022
#
from nornir_netmiko import netmiko_send_command
from nornir_utils.plugins.functions import print_result

from nornir import InitNornir
from nornir.core.task import Result, Task

from colorama import init
from colorama import Fore, Back, Style

''' Skrypt wykorzystuje nornir do wykonywania zdalnie polecen w shell
Po wykonaniu polecen, zbiera wyniki i prezentuje w kolorowej tabelce.'''


KOMENDY = [
    "uptime | awk ' {print $2,$3,$4,$8,$9,$12}'",
    "wc /etc/passwd|  awk '{print \"users:\" $1}'",
    "systemctl list-units --type=service|grep running|wc |awk '{print $1}'",
    "cat ~/.ssh/authorized_keys|wc|awk '{print $1}'",
    "df |grep root | awk '{for(i=1;i<=NF;i++){ if(match($i,/[0-9]+%/)){print $i} } }'"
    ]
LEGENDA = [
    "\t uptime:      load avarage:  ",
    "\t users:",
    "serv running:",
    "ssh keys:",
    "df root:"
]
nr = InitNornir(config_file="config.yaml")


def main_task(task: Task):
    
    for x in KOMENDY:
        task.run(
            task=netmiko_send_command,
            command_string=x
        )
    return Result(
        host=task.host,
        result="Koniec!",
    )


def main(args):
    # inicjujemy kolory w colorama
    init()
    result = nr.run(task=main_task)
    print(Fore.GREEN + "Host",end="\t")
    for a in LEGENDA:
        print(Fore.YELLOW + f"{a}",end="\t")
    for y in result.keys():
        print(Fore.MAGENTA + f"\n{y}", end='\t')
        # pomijamy element 0 - gdyz zawiera on tylko komunikat "Koniec"
        for x in range(1, len(result[y])):
            #print(f"Rezultat: {x} \n")
            print(Fore.CYAN + f" {result[y][x].result}", end='\t')
    print(Style.RESET_ALL)
    # print("\n")


if __name__ == '__main__':
    import sys
    sys.exit(main(sys.argv))

