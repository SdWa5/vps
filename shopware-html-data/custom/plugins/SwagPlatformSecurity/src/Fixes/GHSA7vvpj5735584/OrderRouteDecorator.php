<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSA7vvpj5735584;

use Shopware\Core\Checkout\Cart\CartException;
use Shopware\Core\Checkout\Order\OrderException;
use Shopware\Core\Checkout\Order\SalesChannel\AbstractOrderRoute;
use Shopware\Core\Checkout\Order\SalesChannel\OrderRouteResponse;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Criteria;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\EqualsFilter;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Filter\Filter;
use Shopware\Core\Framework\Feature;
use Shopware\Core\System\SalesChannel\SalesChannelContext;
use Symfony\Component\HttpFoundation\Request;

class OrderRouteDecorator extends AbstractOrderRoute
{
    public function __construct(
        private readonly AbstractOrderRoute $inner
    ) {
    }

    public function getDecorated(): AbstractOrderRoute
    {
        return $this->inner;
    }

    public function load(Request $request, SalesChannelContext $context, Criteria $criteria): OrderRouteResponse
    {
        if ($context->getCustomer() === null) {
            $deepLinkFilter = \current(array_filter($criteria->getFilters(), static fn (Filter $filter) => \in_array('order.deepLinkCode', $filter->getFields(), true)
                || \in_array('deepLinkCode', $filter->getFields(), true))) ?: null;

            if (!$deepLinkFilter instanceof EqualsFilter) {
                if (!Feature::isActive('v6.8.0.0')) {
                    throw CartException::customerNotLoggedIn();
                }
                throw OrderException::customerNotLoggedIn();
            }
        }

        return $this->inner->load($request, $context, $criteria);
    }
}
