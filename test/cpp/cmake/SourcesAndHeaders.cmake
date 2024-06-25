set(sources
    src/basic.cpp
    src/erc20_contract.cpp
    src/service_node_rewards_contract.cpp
    src/service_node_list.cpp
    src/ec_utils.cpp
)

set(headers
    include/service_node_rewards/basic.hpp
    include/service_node_rewards/config.hpp
    include/service_node_rewards/ec_utils.hpp
    include/service_node_rewards/erc20_contract.hpp
    include/service_node_rewards/service_node_rewards_contract.hpp
    include/service_node_rewards/service_node_list.hpp
)

set(test_sources
  src/basic.cpp
  src/basic_ethereum.cpp
  src/rewards_contract.cpp
  src/hash.cpp
)
