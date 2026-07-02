<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAh2x3h9qrcf82;

use Shopware\Commercial\Subscription\Api\Route\Subscription\AbstractSubscriptionPauseRoute;
use Shopware\Commercial\Subscription\Api\Route\Subscription\SubscriptionStateResponse;
use Shopware\Commercial\Subscription\Entity\Subscription\SubscriptionCollection;
use Shopware\Core\Framework\DataAbstractionLayer\EntityRepository;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Criteria;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\EqualsFilter;
use Shopware\Core\System\SalesChannel\SalesChannelContext;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpKernel\Exception\MethodNotAllowedHttpException;

class DecoratedSubscriptionPauseRoute extends AbstractSubscriptionPauseRoute
{
    /**
     * @param EntityRepository<SubscriptionCollection> $subscriptionRepository
     */
    public function __construct(
        private readonly AbstractSubscriptionPauseRoute $inner,
        private readonly EntityRepository $subscriptionRepository,
    ) {
    }

    public function getDecorated(): AbstractSubscriptionPauseRoute
    {
        return $this->inner;
    }

    public function pause(Request $request, SalesChannelContext $context, string $subscriptionId): SubscriptionStateResponse
    {
        if ($request->getMethod() === Request::METHOD_GET) {
            throw new MethodNotAllowedHttpException(['POST']);
        }

        $criteria = new Criteria([$subscriptionId]);
        $criteria->addFilter(new EqualsFilter('subscriptionCustomer.customerId', $context->getCustomer()?->getId()));
        $foundSubscriptionId = $this->subscriptionRepository->searchIds($criteria, $context->getContext())->firstId();
        if ($foundSubscriptionId === null) {
            throw SubscriptionApiException::subscriptionNotFound($subscriptionId);
        }

        return $this->inner->pause($request, $context, $subscriptionId);
    }
}
