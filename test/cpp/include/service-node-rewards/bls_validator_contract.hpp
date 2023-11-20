#include <string>
#include <vector>
#include <memory>

#include "transaction.hpp"
#include "provider.hpp"

class BLSValidatorsContract {
public:
    // Constructor
    BLSValidatorsContract(const std::string& _contractAddress, std::shared_ptr<Provider> _provider);

    // Method for creating a transaction to add a public key
    Transaction addValidator(const std::string& publicKey);

    Transaction clear(uint64_t additional_gas = 0);
    uint64_t getValidatorsLength();

    Transaction checkSigAGG(const std::string& sig, const std::string& message);
    Transaction checkAggPubkey(const std::string& aggPubkey);
    Transaction checkSigAGGIndices(const std::string& sig, const std::string& message, const std::vector<int64_t>& indices);
    Transaction checkSigAGGNegateIndices(const std::string& sig, const std::string& message, const std::vector<int64_t>& non_signer_indices);
    Transaction validateProofOfPossession(const std::string& publicKey, const std::string& sig);
    std::string calcField(const std::string& publicKey);

private:
    std::string contractAddress;
    std::shared_ptr<Provider> provider;
};
