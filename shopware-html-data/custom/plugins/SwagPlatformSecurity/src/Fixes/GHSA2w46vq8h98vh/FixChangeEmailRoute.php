<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSA2w46vq8h98vh;

use Shopware\Core\Checkout\Customer\Aggregate\CustomerRecovery\CustomerRecoveryCollection;
use Shopware\Core\Checkout\Customer\CustomerEntity;
use Shopware\Core\Checkout\Customer\SalesChannel\AbstractChangeEmailRoute;
use Shopware\Core\Framework\DataAbstractionLayer\EntityRepository;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Criteria;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\EqualsFilter;
use Shopware\Core\Framework\Log\Package;
use Shopware\Core\Framework\Validation\DataBag\RequestDataBag;
use Shopware\Core\System\SalesChannel\SalesChannelContext;
use Shopware\Core\System\SalesChannel\SuccessResponse;

#[Package('checkout')]
class FixChangeEmailRoute extends AbstractChangeEmailRoute
{
    /**
     * @param EntityRepository<CustomerRecoveryCollection> $customerRecoveryRepository
     */
    public function __construct(
        private readonly AbstractChangeEmailRoute $decorated,
        private readonly EntityRepository $customerRecoveryRepository
    ) {
    }

    public function getDecorated(): AbstractChangeEmailRoute
    {
        return $this->decorated;
    }

    public function change(RequestDataBag $requestDataBag, SalesChannelContext $context, CustomerEntity $customer): SuccessResponse
    {
        $response = $this->decorated->change($requestDataBag, $context, $customer);

        $criteria = (new Criteria())->addFilter(new EqualsFilter('customerId', $customer->getId()));
        $ids = $this->customerRecoveryRepository->searchIds($criteria, $context->getContext())->getIds();
        if ($ids !== []) {
            $this->customerRecoveryRepository->delete(array_map(static fn ($id) => ['id' => $id], $ids), $context->getContext());
        }

        return $response;
    }
}
