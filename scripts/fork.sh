shopt -s extglob

if [ "$1" == "--no-reset" ]
then 
  chain="$2"
  args="$1 ${@:3}"
else 
  chain="$1"
  args="${@:2}"
fi


echo "forking $chain"
rm -r -f deployments/localhost/!(".chainId") &&
rm -r -f deployments/localhost/.migrations.json &&
rsync -av --exclude='.chainId' deployments/$chain/ deployments/localhost/
case $chain in
  "avalanche")
    FORK_CHAIN=$chain hardhat node --fork https://api.avax.network/ext/bc/C/rpc $args
    ;;
  "fantom")
    FORK_CHAIN=$chain hardhat node --fork https://rpc.ftm.tools/ $args
    ;;
  "moonriver")
    FORK_CHAIN=$chain hardhat node --fork https://rpc.api.moonriver.moonbeam.network $args
    ;;
  "moonbeam")
    FORK_CHAIN=$chain hardhat node --fork https://rpc.api.moonbeam.network $args
    ;;
  *)
    echo -n "unknown chain"
    ;;
esac