<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSA9v5m39wh5chq;

use Shopware\Core\Checkout\Order\OrderCollection;
use Shopware\Core\Checkout\Payment\PaymentException;
use Shopware\Core\Checkout\Payment\SalesChannel\AbstractHandlePaymentMethodRoute;
use Shopware\Core\Checkout\Payment\SalesChannel\HandlePaymentMethodRouteResponse;
use Shopware\Core\Framework\DataAbstractionLayer\EntityRepository;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Criteria;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\EqualsFilter;
use Shopware\Core\System\SalesChannel\SalesChannelContext;
use Symfony\Component\HttpFoundation\Request;

/**
 * GHSA-9v5m-39wh-5chq: Payment processing without customer check.
 * Ensures the order belongs to the current customer before delegating to the inner route.
 */
class HandlePaymentMethodRouteDecorator extends AbstractHandlePaymentMethodRoute
{
    /**
     * @param EntityRepository<OrderCollection> $orderRepository
     */
    public function __construct(
        private readonly AbstractHandlePaymentMethodRoute $inner,
        private readonly EntityRepository $orderRepository,
    ) {
    }

    public function getDecorated(): AbstractHandlePaymentMethodRoute
    {
        return $this->inner;
    }

    public function load(Request $request, SalesChannelContext $context): HandlePaymentMethodRouteResponse
    {
        $data = [...$request->query->all(), ...$request->request->all()];
        $orderId = $data['orderId'] ?? null;

        if (\is_string($orderId) && $orderId !== '') {
            $customer = $context->getCustomer();
            if ($customer === null) {
                throw PaymentException::invalidOrder($orderId);
            }

            $criteria = (new Criteria([$orderId]))
                ->addFilter(new EqualsFilter('orderCustomer.customerId', $customer->getId()))
                ->setLimit(1);

            $queriedId = $this->orderRepository->searchIds($criteria, $context->getContext())->firstId();
            if (!$queriedId) {
                throw PaymentException::invalidOrder($orderId);
            }
        }

        return $this->inner->load($request, $context);
    }
}
