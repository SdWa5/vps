<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAm8952hj38cg9;

use Shopware\Core\Framework\Context;
use Shopware\Core\Framework\DataAbstractionLayer\EntityDefinition;
use Shopware\Core\Framework\DataAbstractionLayer\Search\AggregationResult\AggregationResultCollection;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Criteria;
use Shopware\Core\Framework\DataAbstractionLayer\Search\EntityAggregatorInterface;
use Shopware\Core\Framework\Log\Package;
use Symfony\Component\EventDispatcher\EventDispatcherInterface;

/**
 * @internal
 */
#[Package('framework')]
readonly class EntityAggregatorDecorator implements EntityAggregatorInterface
{
    public function __construct(
        private EntityAggregatorInterface $inner,
        private EventDispatcherInterface $eventDispatcher,
    ) {
    }

    public function aggregate(EntityDefinition $definition, Criteria $criteria, Context $context): AggregationResultCollection
    {
        $this->eventDispatcher->dispatch(new BeforeEntityAggregationEvent($criteria, $definition, $context));

        return $this->inner->aggregate($definition, $criteria, $context);
    }
}
